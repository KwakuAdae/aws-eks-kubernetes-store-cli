#!/usr/bin/env bash
# Step 5: two EKS add-ons
#   metrics-server                    → live CPU/memory per pod (needed by `kubectl top` and the autoscaler)
#   amazon-cloudwatch-observability   → Container Insights: metrics, dashboards and pod logs in CloudWatch
source "$(dirname "$0")/config.sh"

install_addon() {   # install_addon NAME
  if aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$1" >/dev/null 2>&1; then
    echo "   $1 already installed"
  else
    aws eks create-addon --cluster-name "$CLUSTER_NAME" --addon-name "$1" \
      --tags "Project=${PROJECT}" --query 'addon.{name:addonName, status:status}' --output text
  fi
}

step "Add-ons EKS offers for this cluster version (first 30)"
VERSION="$(aws eks describe-cluster --name "$CLUSTER_NAME" --query cluster.version --output text)"
aws eks describe-addon-versions --kubernetes-version "$VERSION" \
  --query 'addons[].addonName' --output text | tr '\t' '\n' | sort | head -30 | paste -sd' ' | fold -s -w 100 | sed 's/^/   /' || true

step "metrics-server"
if install_addon metrics-server; then
  aws eks wait addon-active --cluster-name "$CLUSTER_NAME" --addon-name metrics-server
else
  echo "   the EKS add-on is not available here, installing the upstream release with kubectl instead"
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
fi

step "amazon-cloudwatch-observability (uses the CloudWatchAgentServerPolicy on the node role from step 2)"
install_addon amazon-cloudwatch-observability
aws eks wait addon-active --cluster-name "$CLUSTER_NAME" --addon-name amazon-cloudwatch-observability

step "Installed add-ons"
for addon in $(aws eks list-addons --cluster-name "$CLUSTER_NAME" --query 'addons[]' --output text); do
  aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon" \
    --query 'addon.[addonName, addonVersion, status]' --output text | sed 's/^/   /'
done

step "Waiting for metrics-server to report (Auto Mode may first start a node for it: 1-3 minutes)"
for _ in $(seq 30); do
  kubectl top nodes >/dev/null 2>&1 && break
  printf '.'; sleep 10
done
echo ""
kubectl top nodes || echo "   no metrics yet, it will be ready by the time you need it in step 10"

echo ""
echo "✅ Add-ons ready. Next: ./scripts/06-build-push-image.sh 1.0"
