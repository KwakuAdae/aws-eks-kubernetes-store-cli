#!/usr/bin/env bash
# Step 8: wait for the Network Load Balancer, then show that requests are shared between the pods.
source "$(dirname "$0")/config.sh"

step "Waiting for the load balancer address (usually 1-3 minutes)"
HOST=""
for _ in $(seq 60); do
  HOST="$(kubectl get service kwaku-store -n "$NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  [[ -n "$HOST" ]] && break
  printf '.'; sleep 10
done
echo ""
if [[ -z "$HOST" ]]; then
  echo "❌ No load balancer yet. Check: kubectl describe service kwaku-store -n ${NAMESPACE}" >&2
  exit 1
fi
kubectl get service kwaku-store -n "$NAMESPACE"
save WEBSITE_URL "http://${HOST}"

step "Waiting for DNS and the load balancer health checks (can take 2-5 more minutes)"
for _ in $(seq 60); do
  curl -fs --max-time 5 "${WEBSITE_URL}/health" >/dev/null && break
  printf '.'; sleep 10
done
echo ""
if ! curl -fs --max-time 5 "${WEBSITE_URL}/health" >/dev/null; then
  echo "⚠️  Not answering yet. Try again in a few minutes:  curl -I ${WEBSITE_URL}"
  exit 1
fi

step "10 requests: each answer says which pod served it (load balancing across the pods)"
for _ in $(seq 10); do
  curl -s --max-time 5 "${WEBSITE_URL}/info.json"
done | sed 's/^/   /'

echo ""
echo "✅ Open in your browser:  ${WEBSITE_URL}"
echo "   (http, not https: this project has no TLS certificate). Refresh to see the pod name change."
echo "   Next: ./scripts/09-test-self-healing.sh"
