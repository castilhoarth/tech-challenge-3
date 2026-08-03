#!/bin/bash
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
REPO_PREFIX="${ECR_REPOSITORY_PREFIX:-tech-challenge}"

repos=(
  "auth-service"
  "flag-service"
  "targeting-service"
  "evaluation-service"
  "analytics-service"
)

for repo in "${repos[@]}"; do
  full_name="${REPO_PREFIX}/${repo}"
  echo "Creating ECR repository: ${full_name}"
  aws ecr create-repository \
    --region "${REGION}" \
    --repository-name "${full_name}" \
    --image-scanning-configuration scanOnPush=true >/dev/null
  echo "Created: ${full_name}"
done

echo "Finished creating ECR repositories."
