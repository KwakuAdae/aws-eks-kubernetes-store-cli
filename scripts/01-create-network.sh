#!/usr/bin/env bash
# Step 1: the network. A VPC with 2 public + 2 private subnets in two Availability Zones,
# an internet gateway, and one NAT gateway (~3 minutes, mostly waiting for the NAT gateway).
#
#                  ┌──────────────── VPC 10.0.0.0/16 ────────────────┐
#   internet ◄──► IGW ◄── public-a 10.0.0.0/20   public-b 10.0.16.0/20  (load balancer)
#                            │ NAT gateway
#                            ▼
#                     private-a 10.0.128.0/20  private-b 10.0.144.0/20   (nodes and pods)
source "$(dirname "$0")/config.sh"

if [[ -n "${VPC_ID:-}" ]]; then
  echo "VPC ${VPC_ID} already exists (from .lab-env). Nothing to do."
  exit 0
fi

step "Caller identity and region"
aws sts get-caller-identity --query '{Account:Account, Arn:Arn}' --output table
echo "   Region: ${AWS_REGION}"

step "Picking two Availability Zones"
read -r AZ_A AZ_B < <(aws ec2 describe-availability-zones \
  --filters Name=state,Values=available Name=zone-type,Values=availability-zone \
  --query 'AvailabilityZones[0:2].ZoneName' --output text)
save AZ_A "$AZ_A"
save AZ_B "$AZ_B"

step "VPC ${VPC_CIDR} with DNS hostnames enabled"
save VPC_ID "$(aws ec2 create-vpc --cidr-block "$VPC_CIDR" \
  --tag-specifications "$(tags vpc "${PROJECT}-vpc")" --query Vpc.VpcId --output text)"
aws ec2 wait vpc-available --vpc-ids "$VPC_ID"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'

step "Internet gateway"
save IGW_ID "$(aws ec2 create-internet-gateway \
  --tag-specifications "$(tags internet-gateway "${PROJECT}-igw")" \
  --query InternetGateway.InternetGatewayId --output text)"
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"

step "Subnets (the kubernetes.io/role tags tell EKS where to put load balancers)"
create_subnet() {   # create_subnet NAME CIDR AZ ROLE-TAG
  aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$2" --availability-zone "$3" \
    --tag-specifications "$(tags subnet "$1" "Key=$4,Value=1")" \
    --query Subnet.SubnetId --output text
}
save PUBLIC_SUBNET_A  "$(create_subnet "${PROJECT}-public-a"  10.0.0.0/20   "$AZ_A" kubernetes.io/role/elb)"
save PUBLIC_SUBNET_B  "$(create_subnet "${PROJECT}-public-b"  10.0.16.0/20  "$AZ_B" kubernetes.io/role/elb)"
save PRIVATE_SUBNET_A "$(create_subnet "${PROJECT}-private-a" 10.0.128.0/20 "$AZ_A" kubernetes.io/role/internal-elb)"
save PRIVATE_SUBNET_B "$(create_subnet "${PROJECT}-private-b" 10.0.144.0/20 "$AZ_B" kubernetes.io/role/internal-elb)"
for s in "$PUBLIC_SUBNET_A" "$PUBLIC_SUBNET_B"; do
  aws ec2 modify-subnet-attribute --subnet-id "$s" --map-public-ip-on-launch
done

step "Public route table: 0.0.0.0/0 → internet gateway"
save PUBLIC_RT "$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
  --tag-specifications "$(tags route-table "${PROJECT}-public-rt")" \
  --query RouteTable.RouteTableId --output text)"
aws ec2 create-route --route-table-id "$PUBLIC_RT" --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$IGW_ID" --output text >/dev/null
for s in "$PUBLIC_SUBNET_A" "$PUBLIC_SUBNET_B"; do
  aws ec2 associate-route-table --route-table-id "$PUBLIC_RT" --subnet-id "$s" --output text >/dev/null
done

step "NAT gateway in ${AZ_A} (lets the private nodes download container images) ~2 minutes"
save EIP_ALLOC "$(aws ec2 allocate-address --domain vpc \
  --tag-specifications "$(tags elastic-ip "${PROJECT}-nat-eip")" \
  --query AllocationId --output text)"
save NAT_ID "$(aws ec2 create-nat-gateway --subnet-id "$PUBLIC_SUBNET_A" --allocation-id "$EIP_ALLOC" \
  --tag-specifications "$(tags natgateway "${PROJECT}-nat")" \
  --query NatGateway.NatGatewayId --output text)"
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_ID"

step "Private route table: 0.0.0.0/0 → NAT gateway"
save PRIVATE_RT "$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
  --tag-specifications "$(tags route-table "${PROJECT}-private-rt")" \
  --query RouteTable.RouteTableId --output text)"
aws ec2 create-route --route-table-id "$PRIVATE_RT" --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id "$NAT_ID" --output text >/dev/null
for s in "$PRIVATE_SUBNET_A" "$PRIVATE_SUBNET_B"; do
  aws ec2 associate-route-table --route-table-id "$PRIVATE_RT" --subnet-id "$s" --output text >/dev/null
done

step "Subnets in ${VPC_ID}"
aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query 'Subnets[].{Name:Tags[?Key==`Name`]|[0].Value, CIDR:CidrBlock, AZ:AvailabilityZone, Id:SubnetId}' \
  --output table

echo ""
echo "✅ Network ready. Next: ./scripts/02-create-iam-roles.sh"
