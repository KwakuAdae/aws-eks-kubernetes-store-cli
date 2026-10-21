#!/usr/bin/env bash
# Step 6: build the website image with Docker and push it to a private Amazon ECR repository.
#   ./scripts/06-build-push-image.sh 1.0     (version 1.0, used for the first deployment)
#   ./scripts/06-build-push-image.sh 2.0     (version 2.0, used in step 11 for the rolling update)
source "$(dirname "$0")/config.sh"
VERSION="${1:-1.0}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

step "ECR repository ${ECR_REPO} (scan on push, immutable tags: a version can never be overwritten)"
if aws ecr describe-repositories --repository-names "$ECR_REPO" >/dev/null 2>&1; then
  echo "   already exists"
else
  aws ecr create-repository --repository-name "$ECR_REPO" \
    --image-scanning-configuration scanOnPush=true \
    --image-tag-mutability IMMUTABLE \
    --tags "Key=Project,Value=${PROJECT}" \
    --query 'repository.repositoryUri' --output text
fi
save ECR_URI "${REGISTRY}/${ECR_REPO}"

if aws ecr describe-images --repository-name "$ECR_REPO" --image-ids "imageTag=${VERSION}" >/dev/null 2>&1; then
  echo "   ${ECR_URI}:${VERSION} is already in ECR, nothing to build"
else
  step "docker login to ECR"
  aws ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRY"

  step "docker build (version ${VERSION}, linux/amd64 so it runs on the EKS nodes even if you build on an Apple Silicon Mac)"
  docker build --platform linux/amd64 --build-arg "APP_VERSION=${VERSION}" \
    -t "${ECR_URI}:${VERSION}" "${ROOT_DIR}/app"

  step "docker push"
  docker push "${ECR_URI}:${VERSION}"
fi

step "Images in ECR"
aws ecr describe-images --repository-name "$ECR_REPO" \
  --query 'sort_by(imageDetails, &imagePushedAt)[].{tags:join(`,`, imageTags), pushed:imagePushedAt, sizeBytes:imageSizeInBytes}' \
  --output table

step "Vulnerability scan for ${VERSION} (may say IN_PROGRESS for a minute)"
aws ecr wait image-scan-complete --repository-name "$ECR_REPO" --image-id "imageTag=${VERSION}" 2>/dev/null || true
aws ecr describe-image-scan-findings --repository-name "$ECR_REPO" --image-id "imageTag=${VERSION}" \
  --query 'imageScanFindings.findingSeverityCounts' --output table 2>/dev/null || echo "   scan not finished yet"

echo ""
echo "✅ Image ${ECR_URI}:${VERSION} is in ECR. Next: ./scripts/07-deploy-website.sh"
