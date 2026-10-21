#!/usr/bin/env bash
# Step 11: release version 2.0 with zero downtime, then roll back to 1.0.
#   ./scripts/11-rolling-update.sh            → update to 2.0 (builds and pushes the image if needed)
#   ./scripts/11-rolling-update.sh rollback   → go back to the previous version
source "$(dirname "$0")/config.sh"
require ECR_URI WEBSITE_URL

versions_seen() {   # ask the site 10 times which version answered
  for _ in $(seq 10); do curl -s --max-time 5 "${WEBSITE_URL}/info.json"; done \
    | grep -o '"version":"[^"]*"' | sort | uniq -c | sed 's/^/   /'
}

if [[ "${1:-}" == "rollback" ]]; then
  step "kubectl rollout undo (back to the previous revision)"
  kubectl rollout undo deployment/kwaku-store -n "$NAMESPACE"
else
  VERSION="${1:-2.0}"
  "$(dirname "$0")/06-build-push-image.sh" "$VERSION"

  step "Before: versions answering"
  versions_seen

  step "kubectl set image → version ${VERSION} (one new pod at a time, never fewer than 3 ready)"
  kubectl annotate deployment/kwaku-store -n "$NAMESPACE" --overwrite \
    kubernetes.io/change-cause="update to version ${VERSION}"     # recorded in the rollout history
  kubectl set image deployment/kwaku-store -n "$NAMESPACE" "web=${ECR_URI}:${VERSION}"
fi

kubectl rollout status deployment/kwaku-store -n "$NAMESPACE" --timeout=10m

step "After: versions answering"
sleep 10
versions_seen

step "Rollout history (the change-cause says what each revision was)"
kubectl rollout history deployment/kwaku-store -n "$NAMESPACE"
kubectl get pods -n "$NAMESPACE" -l app=kwaku-store \
  -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image,READY:.status.containerStatuses[0].ready

echo ""
if [[ "${1:-}" == "rollback" ]]; then
  echo "✅ Rolled back. Next: ./scripts/12-monitoring.sh"
else
  echo "✅ Updated. Refresh ${WEBSITE_URL} to see the new version badge."
  echo "   To undo:  ./scripts/11-rolling-update.sh rollback"
fi
