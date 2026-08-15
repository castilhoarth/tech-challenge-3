#!/bin/bash
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}" #Uses AWS_REGION environment variable if set, otherwise defaults to us-east-1
REPO_PREFIX="${ECR_REPOSITORY_PREFIX:-tech-challenge}" #Uses ECR_REPOSITORY_PREFIX environment variable if set, otherwise defaults to tech-challenge

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
    --profile "${AWS_PROFILE:-terraform-account}" \
    --repository-name "${full_name}" \
    --image-scanning-configuration scanOnPush=true >/dev/null
  echo "Created: ${full_name}"
done

echo "Finished creating ECR repositories."
