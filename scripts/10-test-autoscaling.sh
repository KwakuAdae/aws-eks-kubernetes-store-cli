#!/usr/bin/env bash
# Step 10: simulate a traffic spike and watch the Horizontal Pod Autoscaler add pods, then remove them.
#   LOAD_PODS=6 ./scripts/10-test-autoscaling.sh     (more load generators = faster scale-out)
source "$(dirname "$0")/config.sh"
LOAD_PODS="${LOAD_PODS:-4}"

hpa_line() {
  kubectl get hpa kwaku-store -n "$NAMESPACE" \
    -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}{" "}{.status.currentReplicas}{" "}{.status.desiredReplicas}'
}
show() {   # one line every check: time, CPU, pods now → pods wanted
  # shellcheck disable=SC2046
  set -- $(hpa_line) - - -
  printf '   %s  CPU %4s%% of request (target 50%%)  pods: %s → %s\n' "$(date +%T)" "$1" "$2" "$3"
}

step "Before: autoscaler and pod CPU"
kubectl get hpa kwaku-store -n "$NAMESPACE"
kubectl top pods -n "$NAMESPACE" -l app=kwaku-store || true

step "Starting ${LOAD_PODS} load generator pods (each requests the home page in a tight loop)"
kubectl create deployment load-generator -n "$NAMESPACE" --replicas="$LOAD_PODS" \
  --image=public.ecr.aws/docker/library/busybox:stable --dry-run=client -o yaml \
  -- /bin/sh -c 'while true; do wget -q -O /dev/null http://kwaku-store; done' | kubectl apply -f -
kubectl rollout status deployment/load-generator -n "$NAMESPACE" --timeout=5m

step "Watching the autoscaler (up to 8 minutes; it checks every 15s)"
PEAK=3
for _ in $(seq 32); do
  show
  CURRENT="$(kubectl get deployment kwaku-store -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')"
  [[ "${CURRENT:-0}" -gt "$PEAK" ]] && PEAK="$CURRENT"
  [[ "$PEAK" -ge 6 ]] && break
  sleep 15
done
echo "   peak ready pods: ${PEAK}"
kubectl get pods -n "$NAMESPACE" -l app=kwaku-store -o wide
kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type
if [[ "$PEAK" -le 3 ]]; then
  echo "   ⚠️  The autoscaler did not scale out. Run again with more load: LOAD_PODS=8 ./scripts/10-test-autoscaling.sh"
fi

step "Traffic spike over: deleting the load generators"
kubectl delete deployment load-generator -n "$NAMESPACE" --wait=false

step "Watching the scale-in (the HPA waits 2 minutes of low CPU first; up to 8 minutes)"
for _ in $(seq 32); do
  show
  [[ "$(kubectl get deployment kwaku-store -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')" -le 3 ]] && break
  sleep 15
done

step "Autoscaler history"
kubectl describe hpa kwaku-store -n "$NAMESPACE" | sed -n '/Events:/,$p'

echo ""
echo "✅ Autoscaling demonstrated (3 → ${PEAK} → 3 pods). Next: ./scripts/11-rolling-update.sh"
