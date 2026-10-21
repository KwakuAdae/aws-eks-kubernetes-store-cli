#!/usr/bin/env bash
# Step 2: the two IAM roles EKS Auto Mode needs.
#   cluster role: lets EKS manage AWS resources for you (EC2 nodes, load balancers, EBS volumes, networking)
#   node role:    lets the worker nodes join the cluster, pull container images and send
#                 metrics/logs to CloudWatch Container Insights
source "$(dirname "$0")/config.sh"

create_role() {   # create_role NAME TRUST-FILE DESCRIPTION POLICY...
  local name="$1" trust="$2" description="$3"; shift 3
  if aws iam get-role --role-name "$name" >/dev/null 2>&1; then
    echo "   role ${name} already exists, reusing it"
  else
    aws iam create-role --role-name "$name" --description "$description" \
      --assume-role-policy-document "file://${trust}" \
      --tags "Key=Project,Value=${PROJECT}" --output text --query Role.Arn >/dev/null
    echo "   created role ${name}"
  fi
  for policy in "$@"; do
    aws iam attach-role-policy --role-name "$name" --policy-arn "arn:aws:iam::aws:policy/${policy}"
    echo "     + ${policy}"
  done
}

step "Cluster role ${CLUSTER_ROLE_NAME} (trusted by eks.amazonaws.com)"
create_role "$CLUSTER_ROLE_NAME" "$ROOT_DIR/iam/cluster-trust-policy.json" \
  "EKS Auto Mode cluster role for ${CLUSTER_NAME}" \
  AmazonEKSClusterPolicy \
  AmazonEKSComputePolicy \
  AmazonEKSBlockStoragePolicy \
  AmazonEKSLoadBalancingPolicy \
  AmazonEKSNetworkingPolicy
save CLUSTER_ROLE_ARN "$(aws iam get-role --role-name "$CLUSTER_ROLE_NAME" --query Role.Arn --output text)"

step "Node role ${NODE_ROLE_NAME} (trusted by ec2.amazonaws.com)"
create_role "$NODE_ROLE_NAME" "$ROOT_DIR/iam/node-trust-policy.json" \
  "EKS Auto Mode node role for ${CLUSTER_NAME}" \
  AmazonEKSWorkerNodeMinimalPolicy \
  AmazonEC2ContainerRegistryPullOnly \
  CloudWatchAgentServerPolicy
save NODE_ROLE_ARN "$(aws iam get-role --role-name "$NODE_ROLE_NAME" --query Role.Arn --output text)"

echo ""
echo "✅ Roles ready. Next: ./scripts/03-create-cluster.sh"
