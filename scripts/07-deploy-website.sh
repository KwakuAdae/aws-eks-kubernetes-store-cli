#!/usr/bin/env bash
# Step 7: deploy the website: namespace, Deployment (3 pods), Service (load balancer), autoscaler, disruption budget.
#   ./scripts/07-deploy-website.sh        (deploys version 1.0)
source "$(dirname "$0")/config.sh"
require ECR_URI
VERSION="${1:-1.0}"

step "Namespace ${NAMESPACE}"
kubectl apply -f "$ROOT_DIR/k8s/namespace.yaml"

step "Deployment: 3 pods running ${ECR_URI}:${VERSION}"
sed -e "s|__IMAGE__|${ECR_URI}:${VERSION}|" -e "s|__VERSION__|${VERSION}|" "$ROOT_DIR/k8s/deployment.yaml" | kubectl apply -f -

step "Service (Network Load Balancer), HorizontalPodAutoscaler, PodDisruptionBudget"
kubectl apply -f "$ROOT_DIR/k8s/service.yaml" -f "$ROOT_DIR/k8s/hpa.yaml" -f "$ROOT_DIR/k8s/pdb.yaml"

step "Waiting for all 3 pods to be ready (Auto Mode starts nodes for them: 1-3 minutes the first time)"
kubectl rollout status deployment/kwaku-store -n "$NAMESPACE" --timeout=10m

step "What is running"
kubectl get deployment,pods,service,hpa,pdb -n "$NAMESPACE" -o wide
step "Nodes Auto Mode started (zone shows the pods are spread across Availability Zones)"
kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type

echo ""
echo "✅ Website deployed. Next: ./scripts/08-get-website-url.sh"
