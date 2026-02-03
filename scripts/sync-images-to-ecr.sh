#!/bin/bash
# Sync Docker Hub images to ECR
#
# This script pulls images from Docker Hub and pushes them to ECR.
# Run this when you first set up ECR or when you want to update images.
#
# IMPORTANT: Must pull linux/amd64 images for ECS Fargate (not arm64 from Apple Silicon Macs)
#
# Usage:
#   aws-vault exec cochlearis --no-session -- ./scripts/sync-images-to-ecr.sh

set -eo pipefail

REGION="eu-central-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
PLATFORM="linux/amd64"

echo "=== ECR Image Sync ==="
echo "Region: $REGION"
echo "Account: $ACCOUNT_ID"
echo "Registry: $ECR_REGISTRY"
echo "Platform: $PLATFORM (for ECS Fargate)"
echo ""

# Log in to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

# Function to sync an image
sync_image() {
  local source_image="$1"
  local target="$2"
  local ecr_image="$ECR_REGISTRY/$target"

  echo ""
  echo "=== Syncing: $source_image -> $ecr_image ==="

  echo "Pulling $source_image (platform: $PLATFORM)..."
  if ! docker pull --platform "$PLATFORM" "$source_image"; then
    echo "WARNING: Failed to pull $source_image, skipping..."
    return 1
  fi

  echo "Tagging as $ecr_image..."
  docker tag "$source_image" "$ecr_image"

  echo "Pushing to ECR..."
  if ! docker push "$ecr_image"; then
    echo "WARNING: Failed to push $ecr_image (repository may not exist yet)"
    return 1
  fi

  echo "Done: $source_image -> $ecr_image"
}

# Sync all images
sync_image "zulip/docker-zulip:latest" "zulip-docker-zulip:latest"
sync_image "zulip/zulip-postgresql:14" "zulip-postgresql:14"
sync_image "lscr.io/linuxserver/bookstack:latest" "bookstack:latest"
sync_image "mattermost/mattermost-team-edition:latest" "mattermost:latest"
sync_image "outlinewiki/outline:latest" "outline:latest"
sync_image "ghcr.io/zitadel/zitadel:latest" "zitadel:latest"

echo ""
echo "=== Sync Complete ==="
echo "ECR images are ready to use."
