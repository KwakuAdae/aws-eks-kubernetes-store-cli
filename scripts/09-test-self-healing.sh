#!/usr/bin/env bash
# Step 9: break things on purpose and watch Kubernetes repair them, while a "customer" keeps using the site.
#   Test A: delete a pod             → the Deployment creates a replacement
#   Test B: crash the web server     → the kubelet restarts the container (RESTARTS goes up)
#   Test C: delete 2 of 3 pods       → both come back, the site stays up on the remaining pod
source "$(dirname "$0")/config.sh"
require WEBSITE_URL

pods() { kubectl get pods -n "$NAMESPACE" -l app=kwaku-store "$@"; }
ready_count() {
  pods -o jsonpath='{range .items[*]}{.metadata.deletionTimestamp}{" "}{.status.containerStatuses[0].ready}{"\n"}{end}' \
    | grep -c '^ true$' || true
}
live_pods() {   # pod names that are not shutting down
  pods -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.deletionTimestamp}{"\n"}{end}' | awk 'NF == 1 { print $1 }'
}
wait_for_3_ready() {   # prints how many seconds it took
  local start=$SECONDS
  until [[ "$(ready_count)" -ge 3 ]]; do sleep 2; done
  echo $((SECONDS - start))
}

# The "customer": one request every half second for the whole test, results written to a file
PROBE_LOG="$(mktemp)"
( while true; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "${WEBSITE_URL}/health" || true)"
    echo "$(date +%T) ${code}" >> "$PROBE_LOG"
    sleep 0.5
  done ) &
PROBE_PID=$!
trap 'kill $PROBE_PID 2>/dev/null; rm -f "$PROBE_LOG"' EXIT

step "Before: 3 healthy pods"
pods -o wide

step "Test A: delete one pod (as if it had crashed or its node had died)"
VICTIM="$(live_pods | head -1)"
kubectl delete pod "$VICTIM" -n "$NAMESPACE" --wait=false
sleep 2
pods
echo "   ⏱  back to 3 ready pods after $(wait_for_3_ready)s"
pods

step "Test B: stop NGINX inside a pod (the container exits; Kubernetes restarts it in place)"
VICTIM="$(live_pods | head -1)"
BEFORE="$(kubectl get pod "$VICTIM" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].restartCount}')"
kubectl exec "$VICTIM" -n "$NAMESPACE" -- nginx -s stop || true
for _ in $(seq 30); do
  AFTER="$(kubectl get pod "$VICTIM" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].restartCount}')"
  [[ "$AFTER" -gt "$BEFORE" ]] && break
  sleep 2
done
echo "   restart count for ${VICTIM}: ${BEFORE} → ${AFTER}"
echo "   ⏱  back to 3 ready pods after $(wait_for_3_ready)s"
pods

step "Test C: delete 2 of the 3 pods at the same time"
# shellcheck disable=SC2046
kubectl delete pod -n "$NAMESPACE" $(live_pods | head -2) --wait=false
sleep 2
pods
echo "   ⏱  back to 3 ready pods after $(wait_for_3_ready)s"
pods -o wide

step "What Kubernetes did (events)"
kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp \
  --field-selector involvedObject.kind=Pod -o custom-columns=TIME:.lastTimestamp,REASON:.reason,POD:.involvedObject.name,MESSAGE:.message \
  | tail -15

sleep 15   # let the last requests through the load balancer
TOTAL="$(wc -l < "$PROBE_LOG")"
OK="$(grep -c ' 200$' "$PROBE_LOG" || true)"
step "Customer view during the tests"
echo "   requests sent:      ${TOTAL}"
echo "   successful (200):   ${OK}"
echo "   failed:             $((TOTAL - OK))"
echo "   availability:       $(awk -v ok="$OK" -v t="$TOTAL" 'BEGIN { printf "%.1f%%", t ? ok * 100 / t : 0 }')"
if [[ "$OK" -lt "$TOTAL" ]]; then
  echo "   failed requests:"; grep -v ' 200$' "$PROBE_LOG" | sed 's/^/     /' | head -10
  echo "   (a few failures can happen while the load balancer notices a pod has gone; see README → Troubleshooting)"
fi

echo ""
echo "✅ Self-healing demonstrated. Next: ./scripts/10-test-autoscaling.sh"
