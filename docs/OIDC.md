# OIDC SSO Integration - Status & Handoff Document

*Last updated: 2026-02-01*

## Executive Summary

**Goal**: Enable OIDC/SSO for BookStack, Mattermost, Zulip, and Outline via Zitadel identity provider.

**Final State**: **ABANDONED** after 48 hours of troubleshooting over an entire weekend.

**Current Auth Strategy**: Google OAuth for BookStack and Zulip. Username/password as fallback.

---

## Why We Stopped (2026-02-01)

After 48 continuous hours of troubleshooting:

1. **Never saw a single successful OIDC redirect** - not even close
2. **Business deadline** - needed functional services for collaborative event
3. **No progress signal** - each "fix" revealed another layer of problems
4. **Opportunity cost** - Data fabric work (Zenoh/OpenZiti) takes priority

**The final state**: All network infrastructure was verified correct (internal ALB, private DNS, SSL certs, healthy targets), but BookStack still showed "OIDC Discovery Error" when trying to reach the issuer URL that worked perfectly when curled externally.

**What's working now**: Google OAuth - simple, proven, no self-hosted IdP complexity.

---

## If Picking This Up Later

1. **Read this entire document** - it has the full history
2. **Start with a fresh Zitadel database** - the RDS data may be "poisoned" from failed attempts
3. **Consider Zitadel v3 instead of v4** - v4's split Login UI adds significant complexity
4. **Test from inside the VPC** - don't trust external curls, run a test task from ECS
5. **Consider alternatives**: Keycloak, Authentik, Auth0, Okta

**Time estimate to retry**: Budget 2-3 days minimum, with no guarantee of success.

---

## Historical Context (What Was Tried)

---

## Problem History

### Phase 1: Hairpin NAT (Network Layer)

**Original Problem**: ECS Fargate tasks in private subnets couldn't reach `auth.dev.almondbread.org` because it routes through the public ALB, creating a hairpin NAT situation.

**Solution Implemented**:
- Created internal ALB (`cochlearis-dev-internal-alb`)
- Created private Route53 hosted zone pointing `auth.dev.almondbread.org` to internal ALB
- Separate target group for Zitadel on internal ALB
- Modified ECS service module to support multiple `load_balancer` blocks

**Verification**: Test tasks from within VPC can successfully curl `https://auth.dev.almondbread.org/.well-known/openid-configuration` and get valid OIDC discovery JSON.

### Phase 2: App-Layer Issues

After fixing network, OIDC still didn't work. External review identified:

1. **BookStack (Laravel)**: Missing `APP_PROXIES="*"` - Laravel didn't trust ALB proxy headers, generated `http://` callback URLs that Zitadel rejected.

2. **Mattermost**: Wrong OAuth scope - Team Edition uses GitLab adapter requiring `read_user` scope, not standard OIDC `openid profile email` scopes.

**Fixes Applied** (in code, never deployed):
- `modules/aws/apps/bookstack/main.tf`: Added `APP_PROXIES = "*"`
- `modules/aws/apps/mattermost/main.tf`: Changed scope to `read_user`

### Phase 3: Security Group Replacement Disaster

During terraform apply, AWS security group descriptions (immutable) caused replacement attempts. The ALB security group couldn't be replaced because the ALB was still attached. After 15+ minutes of waiting and timeouts, we decided to destroy and rebuild.

**Fix Applied**:
- `modules/aws/alb/main.tf`: Added `lifecycle { ignore_changes = [description] }`

### Phase 4: Terraform Provider Chicken-and-Egg

After destroy, terraform apply failed because the Zitadel Terraform provider tries to connect to Zitadel during initialization - but Zitadel doesn't exist yet on a fresh deploy.

**Errors**:
```
Error: failed to start zitadel client: OpenID Provider Configuration Discovery has failed
Error: failed to start zitadel client: PEM decode failed
```

**Initial Bad Solution**: Commenting out provider blocks (rejected as terrible practice)

**Proper Solution Implemented**: Restructured to use separate Terraform root for OIDC:

```
environments/aws/dev/
├── main.tf              # Core infra - reads OIDC config from SSM
├── terraform.tf         # Only aws/random providers
├── providers.tf         # No zitadel provider
└── oidc/                # NEW: Separate Terraform root
    ├── main.tf          # Creates OIDC clients, writes to SSM
    ├── terraform.tf     # Has zitadel provider
    ├── providers.tf     # Zitadel provider config
    ├── variables.tf
    └── outputs.tf
```

---

## Current State

### Infrastructure: DESTROYED

Everything was destroyed. Nothing is running.

### Code Changes Made (Not Deployed)

1. **Separate OIDC Terraform Root**: `environments/aws/dev/oidc/`
   - Contains zitadel provider
   - Creates OIDC clients in Zitadel
   - Writes client IDs and secret ARNs to SSM Parameter Store

2. **Main Dev Root Updated**: `environments/aws/dev/`
   - Removed zitadel provider entirely
   - Reads OIDC config from SSM when `enable_zitadel_oidc=true`
   - No longer has chicken-and-egg problem

3. **App-Layer OIDC Fixes**:
   - BookStack: `APP_PROXIES="*"`
   - Mattermost: `MM_GITLABSETTINGS_SCOPE="read_user"`

4. **Security Group Fix**:
   - ALB security group ignores description changes

---

## What Needs to Happen

### Deploy Sequence

```bash
# 1. Deploy core infrastructure (Zitadel included, OIDC disabled)
cd environments/aws/dev
# Ensure terraform.tfvars has: enable_zitadel_oidc = false
terraform init
terraform apply

# 2. Wait for Zitadel to be healthy
# Check: https://auth.dev.almondbread.org
# Or check ECS console for healthy Zitadel service

# 3. Run bootstrap script (creates Zitadel service account)
# This may already exist - check SSM for /${project}/${environment}/zitadel/organization-id
./bootstrap-zitadel-oidc.sh

# 4. Deploy OIDC configuration
cd environments/aws/dev/oidc
terraform init
terraform apply

# 5. Enable OIDC in main config
cd environments/aws/dev
# Set terraform.tfvars: enable_zitadel_oidc = true
terraform apply

# 6. Force redeploy apps to pick up OIDC config
aws ecs update-service --cluster cochlearis-dev-cluster --service cochlearis-dev-bookstack --force-new-deployment
aws ecs update-service --cluster cochlearis-dev-cluster --service cochlearis-dev-mattermost --force-new-deployment
# etc for other apps
```

---

## Key Files Reference

### Terraform Configuration
| File | Purpose |
|------|---------|
| `environments/aws/dev/main.tf` | Core infrastructure, reads OIDC from SSM |
| `environments/aws/dev/terraform.tfvars` | `enable_zitadel_oidc` flag |
| `environments/aws/dev/oidc/main.tf` | Creates OIDC clients, writes to SSM |
| `modules/aws/zitadel-oidc/main.tf` | Zitadel OIDC application resources |

### App Modules with OIDC Config
| File | App | OIDC Config Location |
|------|-----|---------------------|
| `modules/aws/apps/bookstack/main.tf` | BookStack | Lines 191-230 (environment_variables) |
| `modules/aws/apps/mattermost/main.tf` | Mattermost | Lines 151-170 (GitLab OAuth) |
| `modules/aws/apps/zulip/main.tf` | Zulip | OIDC env vars section |
| `modules/aws/apps/outline/main.tf` | Outline | OIDC env vars section |

### Documentation
| File | Purpose |
|------|---------|
| `GOTCHAS.md` | Comprehensive lessons learned |
| `OIDC.md` | This file |

---

## SSM Parameter Store Structure (Created by dev/oidc/)

```
/${project}/${environment}/oidc/issuer-url
/${project}/${environment}/oidc/bookstack/client-id
/${project}/${environment}/oidc/bookstack/secret-arn
/${project}/${environment}/oidc/mattermost/client-id
/${project}/${environment}/oidc/mattermost/secret-arn
/${project}/${environment}/oidc/zulip/client-id
/${project}/${environment}/oidc/zulip/secret-arn
/${project}/${environment}/oidc/outline/client-id
/${project}/${environment}/oidc/outline/secret-arn
```

---

## OIDC Client Configuration in Zitadel

### BookStack
- **Redirect URI**: `https://docs.dev.almondbread.org/oidc/callback`
- **Auth Method**: BASIC
- **Grant Types**: authorization_code, refresh_token

### Mattermost (GitLab-style OAuth)
- **Redirect URI**: `https://mm.dev.almondbread.org/signup/gitlab/complete`
- **Auth Method**: BASIC
- **Scope Required**: `read_user` (NOT standard OIDC scopes)

### Zulip
- **Redirect URI**: `https://chat.dev.almondbread.org/complete/oidc/`
- **Auth Method**: BASIC

### Outline
- **Redirect URI**: `https://wiki.dev.almondbread.org/auth/oidc.callback`
- **Auth Method**: BASIC

---

## Environment Variables for Apps

### BookStack
```
AUTH_METHOD = "oidc"
OIDC_NAME = "Zitadel"
OIDC_DISPLAY_NAME_CLAIMS = "name"
OIDC_CLIENT_ID = (from SSM)
OIDC_CLIENT_SECRET = (from Secrets Manager)
OIDC_ISSUER = "https://auth.dev.almondbread.org"
OIDC_ISSUER_DISCOVER = "true"
OIDC_USER_TO_GROUPS = "true"
OIDC_GROUPS_CLAIM = "groups"
APP_PROXIES = "*"  # CRITICAL: Trust ALB proxy headers
```

### Mattermost (Team Edition - GitLab OAuth)
```
MM_GITLABSETTINGS_ENABLE = "true"
MM_GITLABSETTINGS_ID = (from SSM)
MM_GITLABSETTINGS_SECRET = (from Secrets Manager)
MM_GITLABSETTINGS_SCOPE = "read_user"  # CRITICAL: Not standard OIDC scopes
MM_GITLABSETTINGS_AUTHENDPOINT = "https://auth.dev.almondbread.org/oauth/v2/authorize"
MM_GITLABSETTINGS_TOKENENDPOINT = "https://auth.dev.almondbread.org/oauth/v2/token"
MM_GITLABSETTINGS_USERAPIENDPOINT = "https://auth.dev.almondbread.org/oidc/v1/userinfo"
```

---

## Failure History

1. Initial OIDC config without addressing hairpin NAT
2. Multiple debugging attempts with curl/nslookup from inside containers
3. ECS Exec attempts (containers don't have SSM agent)
4. run-task with command overrides
5. Claiming things were "fixed" without verification (multiple times)
6. DNS caching issues (tasks running before DNS change)
7. Force redeployments that didn't pick up correct config
8. Security group replacement timeouts
9. Full destroy due to stuck terraform state
10. Terraform provider chicken-and-egg on fresh deploy
11. Attempted commenting/uncommenting provider code (bad practice)
12. Final restructure to separate Terraform roots

---

## Recommendations for Advisor

1. **Verify the restructure is correct** - The separate `dev/oidc/` root approach may have issues I haven't foreseen

2. **Check Zitadel OIDC client config** - Once deployed, verify in Zitadel admin UI that redirect URIs match exactly

3. **Test apps with debug logging** - BookStack: `APP_DEBUG=true`, Mattermost: check system console

4. **Consider simpler alternatives** - If OIDC continues failing:
   - SAML instead of OIDC
   - Username/password auth for dev environment
   - Different identity provider

5. **Docker Hub rate limits** - Zulip was previously hitting rate limits. Consider mirroring images to ECR.

---

## Commands for Debugging

```bash
# Check ECS service status
aws ecs describe-services --cluster cochlearis-dev-cluster --services cochlearis-dev-bookstack cochlearis-dev-mattermost cochlearis-dev-zitadel

# Check target group health
aws elbv2 describe-target-health --target-group-arn <arn>

# Test OIDC discovery from within VPC
aws ecs run-task \
  --cluster cochlearis-dev-cluster \
  --task-definition cochlearis-dev-zitadel \
  --overrides '{"containerOverrides":[{"name":"zitadel","command":["sh","-c","curl -s https://auth.dev.almondbread.org/.well-known/openid-configuration"]}]}' \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx]}"

# Check SSM parameters
aws ssm get-parameters-by-path --path /cochlearis/dev/oidc/ --recursive

# Force redeploy
aws ecs update-service --cluster cochlearis-dev-cluster --service <service-name> --force-new-deployment
```

---

*This document represents approximately 48 hours of failed attempts and debugging over an entire weekend. The infrastructure was deployed, verified correct at every layer, but OIDC never worked.*

---

## Final Outcome (2026-02-01)

**Decision**: Abandon Zitadel OIDC. Switch to Google OAuth.

**Rationale**:
- Self-hosted IdP is valuable for dogfooding (Zitadel is part of our planned data fabric tech stack)
- However, after 48 hours with zero progress, pragmatism wins
- Event deadline required functional collaboration services
- Google OAuth is proven, simple, and meets immediate needs

**What's preserved for future attempt**:
- All Terraform code for OIDC integration (in `dev/oidc/`)
- Bootstrap scripts
- This documentation
- Network infrastructure (internal ALB, private DNS zone)

**What's now active**:
- Google OAuth for BookStack and Zulip
- Username/password fallback where supported
- `enable_zitadel_oidc = false` in terraform.tfvars
