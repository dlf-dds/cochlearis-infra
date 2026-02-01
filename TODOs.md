# TODOs

## High Priority

### Set Up ECR for Container Images
**Problem**: Docker Hub rate limits (429 Too Many Requests) cause ECS task failures for unauthenticated pulls.

**Plan**:
1. Create ECR repositories for each image:
   - `zulip/docker-zulip`
   - `zulip/zulip-postgresql`
   - `linuxserver/bookstack`
   - `mattermost/mattermost-team-edition`
   - `ghcr.io/zitadel/zitadel` (optional - GHCR has higher limits)

2. Create terraform module for ECR repositories:
   ```hcl
   # modules/aws/ecr/main.tf
   resource "aws_ecr_repository" "main" {
     for_each = var.repositories
     name     = each.key

     image_scanning_configuration {
       scan_on_push = true
     }
   }
   ```

3. One-time image sync script:
   ```bash
   #!/bin/bash
   # scripts/sync-images-to-ecr.sh
   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   REGION=eu-central-1

   aws ecr get-login-password --region $REGION | \
     docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

   images=(
     "zulip/docker-zulip:latest"
     "zulip/zulip-postgresql:14"
     "linuxserver/bookstack:latest"
     "mattermost/mattermost-team-edition:latest"
   )

   for image in "${images[@]}"; do
     docker pull $image
     ecr_image="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$image"
     docker tag $image $ecr_image
     docker push $ecr_image
   done
   ```

4. Update app modules to use ECR URLs:
   - Add `container_registry` variable to each app module
   - Default to ECR, allow override for local dev

5. Consider automated sync (optional):
   - Lambda function on schedule to pull and push new versions
   - Or GitHub Actions workflow

**Estimated effort**: 2-3 hours for initial setup

---

## Medium Priority

### Debug BookStack OIDC Login
- OIDC discovery works (verified via curl)
- Login button may not appear or redirect may fail
- Check BookStack logs for OIDC-related errors
- Verify callback URL matches Zitadel configuration

### Debug Mattermost OIDC Login
- Uses GitLab-style OAuth adapter
- Check if "GitLab" login button appears
- Verify callback URL: `/signup/gitlab/complete`

### Clean Up Terraform State
- Apply full terraform plan to sync state
- Remove manually-added security group rules (let terraform manage)
- Address ALB security group description change

---

## Low Priority

### Improve Monitoring
- Add CloudWatch alarms for ECS task failures
- Add ALB 5xx error alerting
- Dashboard for service health

### Documentation
- Update README with internal ALB architecture
- Document OIDC troubleshooting steps
- Add runbook for common issues
