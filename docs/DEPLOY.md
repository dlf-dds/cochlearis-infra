# Deployment Guide

Step-by-step guide for deploying the Cochlearis infrastructure.

> **Note (2026-02-02)**: Zitadel OIDC integration is **on hold**. The current deployment uses Azure AD/Google OAuth for most services and Slack OAuth for Outline (works with any Slack workspace). Steps 3-7 below are preserved for future reference if OIDC is revisited.

## Prerequisites

- AWS credentials configured via `aws-vault` with `cochlearis` profile
- Terraform >= 1.7.0
- `jq` installed

**All AWS commands should be prefixed with:**
```bash
aws-vault exec cochlearis --no-session -- <command>
```

## Fresh Deployment (From Scratch)

### Step 1: Deploy Core Infrastructure

```bash
cd environments/aws/dev

# Ensure OIDC is disabled (current default)
# In terraform.tfvars: enable_zitadel_oidc = false

terraform init
aws-vault exec cochlearis --no-session -- terraform apply
```

This creates: VPC, ALB, ECS cluster, RDS databases, all applications including Zitadel.

### Step 2: Configure Authentication

**Current authentication methods (no OIDC):**
- **BookStack, Zulip, Mattermost**: Azure AD / Google OAuth (configure in terraform.tfvars)
- **Outline**: Slack OAuth (configure `outline_slack_client_id` and `outline_slack_secret_arn` in terraform.tfvars)
- **Docusaurus**: Optional ALB OIDC or public (no auth)

**To enable Azure AD or Google OAuth**, set these in terraform.tfvars:
```hcl
enable_azure_oauth      = true
azure_tenant_id         = "your-tenant-id"
azure_client_id         = "your-client-id"
azure_client_secret_arn = "arn:aws:secretsmanager:..."

# Or Google OAuth
enable_google_oauth     = true
google_oauth_client_id  = "your-client-id"
google_oauth_secret_arn = "arn:aws:secretsmanager:..."
```

### Step 3: Configure Slack OAuth for Outline

Outline REQUIRES an OAuth provider. Slack OAuth is recommended because it works with any Slack workspace (free/personal).

1. Create a Slack app at https://api.slack.com/apps
2. Configure redirect URL: `https://wiki.dev.almondbread.org/auth/slack.callback`
3. Store the client secret in AWS Secrets Manager (JSON with 'client_secret' key)
4. Add to terraform.tfvars:
   ```hcl
   outline_slack_client_id  = "your-client-id"
   outline_slack_secret_arn = "arn:aws:secretsmanager:..."
   ```

See [GOTCHAS.md](GOTCHAS.md) for detailed Slack OAuth setup instructions.

---

## Zitadel OIDC Setup (On Hold)

> **Warning**: The following steps are preserved for future reference. Zitadel OIDC was attempted for 48 hours without success. See [OIDC.md](OIDC.md) for details.

### Step 3 (OIDC): Wait for Zitadel Health

Check Zitadel is responding:
```bash
curl -s https://auth.dev.almondbread.org/.well-known/openid-configuration | head -c 100
```

Or check ECS service status:
```bash
aws-vault exec cochlearis --no-session -- aws ecs describe-services \
  --cluster cochlearis-dev-cluster \
  --services zitadel \
  --region eu-central-1 \
  --query 'services[0].{status:status,running:runningCount}'
```

### Step 4 (OIDC): Create Zitadel Service User (Manual Step)

This is the ONE manual step required. PATs in Zitadel require a service user.

1. **Get admin password:**
   ```bash
   aws-vault exec cochlearis --no-session -- aws secretsmanager get-secret-value \
     --secret-id cochlearis-dev-zitadel-master-key \
     --region eu-central-1 \
     --query 'SecretString' --output text | jq -r '.admin_password'
   ```

   Note: Secret name may have a random suffix. List secrets to find it:
   ```bash
   aws-vault exec cochlearis --no-session -- aws secretsmanager list-secrets \
     --region eu-central-1 --filters Key=name,Values=cochlearis-dev-zitadel-master-key \
     --query 'SecretList[*].Name'
   ```

2. **Log into Zitadel console:** https://auth.dev.almondbread.org/ui/console
   - Username: `admin@zitadel.auth.dev.almondbread.org`
   - Password: (from step above)

3. **Create service user:**
   - Left sidebar → Organization → Service Users → +New
   - Username: `terraform-bootstrap`
   - Grant **ORG_OWNER** role

4. **Create Personal Access Token (PAT):**
   - Click the service user → scroll to "Personal Access Tokens" → +New
   - Copy the token immediately (won't be shown again)

### Step 5 (OIDC): Run Bootstrap Script

```bash
cd environments/aws/dev
ZITADEL_PAT="<paste-token-here>" ./bootstrap-zitadel-oidc.sh
```

This creates:
- A `terraform-oidc` service account in Zitadel with IAM_OWNER permissions
- Stores the service account JWT key in AWS Secrets Manager
- Stores the organization ID in SSM Parameter Store

### Step 6 (OIDC): Deploy OIDC Configuration

```bash
cd environments/aws/dev/oidc
terraform init
aws-vault exec cochlearis --no-session -- terraform apply
```

This creates OIDC applications in Zitadel for each app and stores credentials in SSM/Secrets Manager.

### Step 7 (OIDC): Enable OIDC for Applications

```bash
cd environments/aws/dev

# Edit terraform.tfvars:
# enable_zitadel_oidc = true

aws-vault exec cochlearis --no-session -- terraform apply
```

This updates ECS task definitions with OIDC environment variables. ECS will automatically deploy new tasks.

### Step 8 (OIDC): Verify

Test OIDC login on each application:
- BookStack: https://docs.dev.almondbread.org
- Mattermost: https://mm.dev.almondbread.org
- Zulip: https://chat.dev.almondbread.org
- Outline: https://wiki.dev.almondbread.org

---

## Redeployment (Database Survived)

If RDS databases survived a `terraform destroy` (common scenario), you'll need to import existing Zitadel resources.

### Check if Database Survived

```bash
aws-vault exec cochlearis --no-session -- aws rds describe-db-instances \
  --region eu-central-1 \
  --query 'DBInstances[?contains(DBInstanceIdentifier, `zitadel`)].{ID:DBInstanceIdentifier,Created:InstanceCreateTime}'
```

If the creation time predates your destroy, the data survived.

### Import Existing Resources

After running `terraform apply` in `dev/oidc/`, if you get "already exists" errors:

**Option A: Use the helper script (recommended)**
```bash
cd environments/aws/dev
ZITADEL_PAT="<your-pat>" ./list-zitadel-resources.sh
```

This outputs ready-to-use terraform import commands. Run them in `dev/oidc/`.

**Option B: Manual lookup**

1. **Find IDs in Zitadel UI:**
   - Project ID: Projects → click project → ID in URL
   - App IDs: Projects → Apps → click app → ID in URL

2. **Import project:**
   ```bash
   cd environments/aws/dev/oidc
   aws-vault exec cochlearis --no-session -- terraform import \
     'module.zitadel_oidc.zitadel_project.main' '<project-id>'
   ```

3. **Import OIDC applications:**
   ```bash
   aws-vault exec cochlearis --no-session -- terraform import \
     'module.zitadel_oidc.zitadel_application_oidc.bookstack' '<app-id>:<project-id>'

   aws-vault exec cochlearis --no-session -- terraform import \
     'module.zitadel_oidc.zitadel_application_oidc.mattermost' '<app-id>:<project-id>'

   aws-vault exec cochlearis --no-session -- terraform import \
     'module.zitadel_oidc.zitadel_application_oidc.zulip' '<app-id>:<project-id>'
   ```

4. **Re-run apply:**
   ```bash
   aws-vault exec cochlearis --no-session -- terraform apply
   ```

---

## Force Redeploy ECS Services

If services need to pick up configuration changes:

```bash
aws-vault exec cochlearis --no-session -- aws ecs update-service \
  --cluster cochlearis-dev-cluster \
  --service bookstack \
  --force-new-deployment \
  --region eu-central-1

# Repeat for other services: mattermost, zulip, outline, zitadel
```

---

## Troubleshooting

### Check ECS Service Status
```bash
aws-vault exec cochlearis --no-session -- aws ecs describe-services \
  --cluster cochlearis-dev-cluster \
  --services bookstack mattermost zulip zitadel outline \
  --region eu-central-1 \
  --query 'services[*].{name:serviceName,status:status,running:runningCount,desired:desiredCount}'
```

### View ECS Task Logs
```bash
# Get task ARN
aws-vault exec cochlearis --no-session -- aws ecs list-tasks \
  --cluster cochlearis-dev-cluster \
  --service-name bookstack \
  --region eu-central-1

# View logs (requires CloudWatch log group)
aws-vault exec cochlearis --no-session -- aws logs tail \
  /ecs/cochlearis-dev-bookstack \
  --region eu-central-1 \
  --follow
```

### Test OIDC Discovery from VPC
```bash
# Run a test task that curls the OIDC endpoint
# Useful to verify hairpin NAT fix is working
curl -s https://auth.dev.almondbread.org/.well-known/openid-configuration
```

### Check SSM Parameters
```bash
aws-vault exec cochlearis --no-session -- aws ssm get-parameters-by-path \
  --path /cochlearis/dev/oidc/ \
  --recursive \
  --region eu-central-1 \
  --query 'Parameters[*].Name'
```

---

## Application URLs

| Application | URL | Health Check |
|-------------|-----|--------------|
| Zitadel | https://auth.dev.almondbread.org | `/debug/healthz` |
| BookStack | https://docs.dev.almondbread.org | `/status` |
| Mattermost | https://mm.dev.almondbread.org | `/api/v4/system/ping` |
| Zulip | https://chat.dev.almondbread.org | `/login/` |
| Outline | https://wiki.dev.almondbread.org | `/` |
| Docusaurus | https://www.dev.almondbread.org | `/` |

---

## Key Files

| File | Purpose |
|------|---------|
| `environments/aws/dev/main.tf` | Core infrastructure |
| `environments/aws/dev/terraform.tfvars` | Environment config, `enable_zitadel_oidc` flag |
| `environments/aws/dev/oidc/` | Separate Terraform root for OIDC |
| `environments/aws/dev/bootstrap-zitadel-oidc.sh` | Creates Zitadel service account |
| `environments/aws/dev/list-zitadel-resources.sh` | Lists Zitadel resources for terraform import |
| `GOTCHAS.md` | Troubleshooting specific issues |
| `GUIDERAILS.md` | Project context and architecture |
