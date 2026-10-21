#!/usr/bin/env bash
# Delete everything, in the order AWS needs:
#   Service (removes the load balancer) → add-ons → cluster (removes Auto Mode nodes) → NAT gateway →
#   Elastic IP → internet gateway → subnets → route tables → VPC → IAM roles → ECR → CloudWatch
# Resources are found by their Project tag, so this works even without .lab-env.
source "$(dirname "$0")/config.sh"
set +e   # keep cleaning up even if one resource is already gone

VPC_ID="$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=${PROJECT}" --query 'Vpcs[0].VpcId' --output text)"
[[ "$VPC_ID" == "None" ]] && VPC_ID=""

if aws eks describe-cluster --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  step "Deleting the website Service first, so EKS removes its load balancer"
  aws eks update-kubeconfig --name "$CLUSTER_NAME" >/dev/null
  kubectl delete service kwaku-store -n "$NAMESPACE" --ignore-not-found --timeout=5m
  if [[ -n "$VPC_ID" ]]; then
    for _ in $(seq 30); do
      N="$(aws elbv2 describe-load-balancers --query "length(LoadBalancers[?VpcId=='${VPC_ID}'])" --output text)"
      [[ "$N" == "0" ]] && break
      echo "   waiting for ${N} load balancer(s) to be deleted..."; sleep 10
    done
  fi
  kubectl delete namespace "$NAMESPACE" --ignore-not-found --timeout=5m

  step "Deleting the add-ons"
  for addon in $(aws eks list-addons --cluster-name "$CLUSTER_NAME" --query 'addons[]' --output text); do
    aws eks delete-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon" --output text >/dev/null && echo "   deleting ${addon}"
  done
  for addon in $(aws eks list-addons --cluster-name "$CLUSTER_NAME" --query 'addons[]' --output text); do
    aws eks wait addon-deleted --cluster-name "$CLUSTER_NAME" --addon-name "$addon"
  done

  step "Deleting cluster ${CLUSTER_NAME} (~5-10 minutes)"
  aws eks delete-cluster --name "$CLUSTER_NAME" --query cluster.status --output text
  aws eks wait cluster-deleted --name "$CLUSTER_NAME"
else
  echo "   cluster ${CLUSTER_NAME} not found, skipping"
fi

if [[ -n "$VPC_ID" ]]; then
  step "Waiting for Auto Mode EC2 instances in ${VPC_ID} to terminate"
  for _ in $(seq 30); do
    N="$(aws ec2 describe-instances --filters "Name=vpc-id,Values=${VPC_ID}" \
      "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped" \
      --query 'length(Reservations[].Instances[])' --output text)"
    [[ "$N" == "0" ]] && break
    echo "   ${N} instance(s) still shutting down..."; sleep 10
  done

  step "NAT gateway and Elastic IP"
  for nat in $(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=${VPC_ID}" \
      "Name=state,Values=pending,available" --query 'NatGateways[].NatGatewayId' --output text); do
    aws ec2 delete-nat-gateway --nat-gateway-id "$nat" --output text >/dev/null && echo "   deleting ${nat}"
    aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$nat"
  done
  for eip in $(aws ec2 describe-addresses --filters "Name=tag:Project,Values=${PROJECT}" \
      --query 'Addresses[].AllocationId' --output text); do
    aws ec2 release-address --allocation-id "$eip" && echo "   released ${eip}"
  done

  step "Leftover network interfaces and security groups (from the load balancer / nodes)"
  for _ in $(seq 18); do
    ENIS="$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query 'NetworkInterfaces[].NetworkInterfaceId' --output text)"
    [[ -z "$ENIS" ]] && break
    for eni in $ENIS; do aws ec2 delete-network-interface --network-interface-id "$eni" 2>/dev/null; done
    echo "   waiting for network interfaces to be released..."; sleep 10
  done
  for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query "SecurityGroups[?GroupName!='default'].GroupId" --output text); do
    aws ec2 delete-security-group --group-id "$sg" && echo "   deleted ${sg}"
  done

  step "Internet gateway, subnets, route tables, VPC"
  for igw in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
      --query 'InternetGateways[].InternetGatewayId' --output text); do
    aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC_ID"
    aws ec2 delete-internet-gateway --internet-gateway-id "$igw" && echo "   deleted ${igw}"
  done
  for assoc in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query 'RouteTables[].Associations[?!Main].RouteTableAssociationId' --output text); do
    aws ec2 disassociate-route-table --association-id "$assoc"
  done
  for subnet in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query 'Subnets[].SubnetId' --output text); do
    aws ec2 delete-subnet --subnet-id "$subnet" && echo "   deleted ${subnet}"
  done
  for rt in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query 'RouteTables[?!(Associations[?Main])].RouteTableId' --output text); do
    aws ec2 delete-route-table --route-table-id "$rt" && echo "   deleted ${rt}"
  done
  aws ec2 delete-vpc --vpc-id "$VPC_ID" && echo "   deleted ${VPC_ID}"
else
  echo "   no VPC tagged Project=${PROJECT}, skipping network"
fi

step "IAM roles (only the two this lab created)"
for role in "$CLUSTER_ROLE_NAME" "$NODE_ROLE_NAME"; do
  if aws iam get-role --role-name "$role" >/dev/null 2>&1; then
    for arn in $(aws iam list-attached-role-policies --role-name "$role" \
        --query 'AttachedPolicies[].PolicyArn' --output text); do
      aws iam detach-role-policy --role-name "$role" --policy-arn "$arn"
    done
    aws iam delete-role --role-name "$role" && echo "   deleted ${role}"
  fi
done

step "ECR repository ${ECR_REPO} (and every image in it)"
aws ecr delete-repository --repository-name "$ECR_REPO" --force --output text >/dev/null 2>&1 \
  && echo "   deleted ${ECR_REPO}" || echo "   not found, skipping"

step "CloudWatch alarm and Container Insights log groups"
aws cloudwatch delete-alarms --alarm-names "${PROJECT}-pod-restarts" && echo "   deleted alarm ${PROJECT}-pod-restarts"
for group in $(aws logs describe-log-groups --log-group-name-prefix "/aws/containerinsights/${CLUSTER_NAME}/" \
    --query 'logGroups[].logGroupName' --output text); do
  aws logs delete-log-group --log-group-name "$group" && echo "   deleted ${group}"
done
for group in $(aws logs describe-log-groups --log-group-name-prefix "/aws/eks/${CLUSTER_NAME}/" \
    --query 'logGroups[].logGroupName' --output text); do
  aws logs delete-log-group --log-group-name "$group" && echo "   deleted ${group}"
done

rm -f "$LAB_ENV" "${ROOT_DIR}/cluster.json"
kubectl config delete-context "$(kubectl config get-contexts -o name 2>/dev/null | grep "cluster/${CLUSTER_NAME}$")" >/dev/null 2>&1

echo ""
echo "✅ Done. Double-check in the console: EKS → Clusters, EC2 → Load Balancers, VPC → NAT gateways, ECR → Repositories."
