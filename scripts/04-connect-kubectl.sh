#!/usr/bin/env bash
# Step 4: point kubectl at the cluster and look around.
source "$(dirname "$0")/config.sh"

step "aws eks update-kubeconfig (saves the connection details kubectl needs in ~/.kube/config)"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

step "Current context"
kubectl config current-context

step "kubectl cluster-info"
kubectl cluster-info

step "Tool versions (kubectl should be within one minor version of the cluster)"
aws --version
kubectl version 2>/dev/null | sed 's/^/   /' || true

step "Nodes (Auto Mode starts nodes only when pods need them, so 'No resources found' is normal now)"
kubectl get nodes -o wide 2>&1 || true

step "Auto Mode node pools"
kubectl get nodepools 2>&1 || true

echo ""
echo "✅ Connected. Next: ./scripts/05-install-addons.sh"
