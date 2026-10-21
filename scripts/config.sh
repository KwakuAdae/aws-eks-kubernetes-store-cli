#!/usr/bin/env bash
# Shared settings for every step. Override any value by exporting it before running a script.
set -euo pipefail

export AWS_REGION="${AWS_REGION:-eu-west-2}"          # Europe (London)
export AWS_DEFAULT_REGION="$AWS_REGION"
export AWS_PAGER=""                                   # print AWS CLI output straight to the terminal
export PROJECT="${PROJECT:-kwaku-store-eks}"            # tag on every network resource
export CLUSTER_NAME="${CLUSTER_NAME:-kwaku-store-eks}"
export CLUSTER_ROLE_NAME="${CLUSTER_ROLE_NAME:-${PROJECT}-cluster-role}"
export NODE_ROLE_NAME="${NODE_ROLE_NAME:-${PROJECT}-node-role}"
export NAMESPACE="${NAMESPACE:-kwaku-store}"
export ECR_REPO="${ECR_REPO:-kwaku-store-k8s}"
export VPC_CIDR="${VPC_CIDR:-10.0.0.0/16}"
export KUBERNETES_VERSION="${KUBERNETES_VERSION:-}"     # empty = the default version EKS recommends

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB_ENV="${ROOT_DIR}/.lab-env"

# IDs created by earlier steps are saved here so later steps can use them
touch "$LAB_ENV"
# shellcheck disable=SC1090
source "$LAB_ENV"

save() {   # save NAME VALUE → remembered for later steps
  grep -v "^export $1=" "$LAB_ENV" > "${LAB_ENV}.tmp" || true
  echo "export $1=\"$2\"" >> "${LAB_ENV}.tmp"
  mv "${LAB_ENV}.tmp" "$LAB_ENV"
  export "$1=$2"
  echo "   $1=$2"
}

require() {
  for name in "$@"; do
    if [[ -z "${!name:-}" ]]; then
      echo "❌ ${name} is not set. Run the earlier steps first (see README)." >&2
      exit 1
    fi
  done
}

# Tag specification for `aws ec2 create-*`:  tags <resource-type> <name> [extra Key=..,Value=.. ...]
tags() {
  local type="$1" name="$2"; shift 2
  local extra=""
  for kv in "$@"; do extra+=",{${kv}}"; done
  echo "ResourceType=${type},Tags=[{Key=Name,Value=${name}},{Key=Project,Value=${PROJECT}}${extra}]"
}

step() { echo ""; echo "▶ $*"; }
