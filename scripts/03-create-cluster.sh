#!/usr/bin/env bash
# Step 3: the EKS cluster in Auto Mode (~10-15 minutes).
# Auto Mode = AWS also runs the worker nodes, load balancer controller and storage driver for you.
source "$(dirname "$0")/config.sh"
require PRIVATE_SUBNET_A PRIVATE_SUBNET_B CLUSTER_ROLE_ARN NODE_ROLE_ARN

INPUT="${ROOT_DIR}/cluster.json"
step "Writing the cluster request to cluster.json (open it to see every setting)"
python3 - "$INPUT" <<'PY'
import json, os, sys
config = {
    "name": os.environ["CLUSTER_NAME"],
    "roleArn": os.environ["CLUSTER_ROLE_ARN"],
    # Nodes live in the private subnets; the public API endpoint lets CloudShell and your laptop connect
    "resourcesVpcConfig": {
        "subnetIds": [os.environ["PRIVATE_SUBNET_A"], os.environ["PRIVATE_SUBNET_B"]],
        "endpointPublicAccess": True,
        "endpointPrivateAccess": True,
    },
    # Access entries (API) instead of the old aws-auth ConfigMap; you get cluster admin as the creator
    "accessConfig": {
        "authenticationMode": "API",
        "bootstrapClusterCreatorAdminPermissions": True,
    },
    # The three Auto Mode switches: compute, load balancing, block storage (all on together)
    "computeConfig": {
        "enabled": True,
        "nodeRoleArn": os.environ["NODE_ROLE_ARN"],
        "nodePools": ["general-purpose", "system"],
    },
    "kubernetesNetworkConfig": {"elasticLoadBalancing": {"enabled": True}},
    "storageConfig": {"blockStorage": {"enabled": True}},
    # Auto Mode provides networking/DNS itself, so EKS should not install the classic add-ons
    "bootstrapSelfManagedAddons": False,
    "tags": {"Project": os.environ["PROJECT"]},
}
if os.environ.get("KUBERNETES_VERSION"):
    config["version"] = os.environ["KUBERNETES_VERSION"]
with open(sys.argv[1], "w") as f:
    json.dump(config, f, indent=2)
PY
cat "$INPUT"

if aws eks describe-cluster --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  echo "   cluster ${CLUSTER_NAME} already exists, skipping create"
else
  step "aws eks create-cluster --cli-input-json file://cluster.json"
  aws eks create-cluster --cli-input-json "file://${INPUT}" \
    --query 'cluster.{name:name, status:status, version:version}' --output table
fi

step "Waiting for status ACTIVE (check progress any time: aws eks describe-cluster --name ${CLUSTER_NAME} --query cluster.status)"
until aws eks wait cluster-active --name "$CLUSTER_NAME" 2>/dev/null; do
  echo "   still $(aws eks describe-cluster --name "$CLUSTER_NAME" --query cluster.status --output text)..."
done

aws eks describe-cluster --name "$CLUSTER_NAME" \
  --query 'cluster.{name:name, status:status, version:version, endpoint:endpoint, autoMode:computeConfig.enabled}' \
  --output table
echo "   node pools: $(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.computeConfig.nodePools' --output text)"

echo ""
echo "✅ Cluster is ACTIVE. Next: ./scripts/04-connect-kubectl.sh"
