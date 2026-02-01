# OIDC SSO Integration - Problem Summary

## The Problem

We are trying to enable OIDC/SSO for three applications (BookStack, Mattermost, Zulip) via Zitadel as the identity provider. None of them work.

### Root Cause: Hairpin NAT

ECS Fargate tasks in private subnets cannot reach public URLs (like `auth.dev.almondbread.org`) that route back to the same ALB they're behind. This is called "hairpin NAT" or "NAT loopback" - the traffic goes out to the internet, hits the public ALB IP, and the response can't route back to the originating container.

**Symptoms:**
- OIDC discovery fails (`/.well-known/openid-configuration` unreachable)
- Apps redirect users to `/login` instead of Zitadel
- No OIDC-related errors in logs (fails silently)

## Our Approach

### 1. Internal ALB Architecture (Implemented)
Created a separate internal ALB for service-to-service communication:
- Internal ALB with private IPs in the VPC
- Separate target group for Zitadel on the internal ALB
- Private Route53 hosted zone that points `auth.dev.almondbread.org` to the internal ALB
- Modified ECS service module to support multiple load balancer blocks

### 2. DNS Verification (Verified Working)
- Test tasks from within the VPC successfully resolve DNS to internal ALB IPs
- Test tasks can successfully retrieve OIDC discovery JSON from `https://auth.dev.almondbread.org/.well-known/openid-configuration`
- Internal target group shows healthy

### 3. Force Redeployments (Done)
- BookStack and Mattermost services force-redeployed to pick up new DNS
- Confirmed new tasks started after DNS changes

## Current Status

| Application | Status | Details |
|-------------|--------|---------|
| BookStack | NOT WORKING | POST `/oidc/login` returns 302 redirect to `/login`. No OIDC errors in logs. Test tasks from same VPC work. |
| Mattermost | NOT WORKING | GitLab SSO button does not appear on login page despite environment variables being configured. |
| Zulip | DOWN | Docker Hub rate limits (429 Too Many Requests). Separate issue from OIDC. |

## Resources Referenced

### Files Modified
- `modules/aws/ecs-service/main.tf` - Added dynamic load_balancer blocks for multiple target groups
- `modules/aws/ecs-cluster/main.tf` - Added security group rules for internal ALB
- `modules/aws/apps/bookstack/main.tf` - BookStack OIDC configuration
- `modules/aws/apps/mattermost/main.tf` - Mattermost OIDC configuration (GitLab-style OAuth)
- `modules/aws/zitadel-oidc/main.tf` - Zitadel OIDC application definitions
- `environments/aws/dev/main.tf` - Internal ALB target group, listener rules, private DNS zone
- `gotchas.md` - Documented DNS caching issue

### Zitadel OIDC Client Configuration
- BookStack redirect URI: `https://docs.dev.almondbread.org/oidc/callback`
- Mattermost redirect URI: `https://mm.dev.almondbread.org/signup/gitlab/complete`
- Both configured with `auth_method_type = OIDC_AUTH_METHOD_TYPE_BASIC`

### Infrastructure Verified
- Internal ALB: Healthy, serving HTTPS on port 443
- Internal target group: Healthy
- Private DNS: Points to internal ALB IPs (10.0.11.x, 10.0.12.x, 10.0.13.x)
- Test tasks: Successfully retrieve OIDC discovery

## Identified Root Causes (Updated 2026-02-01)

After external review, we identified two **app-layer configuration issues** that explain why network worked but OIDC failed:

### 1. BookStack: Missing Proxy Trust (Laravel)

**Problem:** BookStack (Laravel) behind ALB doesn't know the original request was HTTPS because ALB terminates SSL. Without trusting proxy headers, Laravel generates `http://` callback URLs which Zitadel rejects.

**Fix Applied:**
```hcl
APP_PROXIES = "*"  # Trust X-Forwarded-Proto header from ALB
```
File: `modules/aws/apps/bookstack/main.tf`

### 2. Mattermost: Wrong OAuth Scope

**Problem:** Mattermost Team Edition uses GitLab-style OAuth adapter which requires `read_user` scope. We had `openid profile email` (standard OIDC scopes) which the GitLab adapter doesn't recognize, causing the SSO button to not appear.

**Fix Applied:**
```hcl
MM_GITLABSETTINGS_SCOPE = "read_user"  # Was: "openid profile email"
```
File: `modules/aws/apps/mattermost/main.tf`

## Next Steps

1. **Run `terraform apply`** to update task definitions with new environment variables
2. **Force redeploy both services** to pick up the changes:
   ```bash
   aws-vault exec cochlearis --no-session -- aws ecs update-service \
     --cluster cochlearis-dev-cluster --service cochlearis-dev-bookstack --force-new-deployment
   aws-vault exec cochlearis --no-session -- aws ecs update-service \
     --cluster cochlearis-dev-cluster --service cochlearis-dev-mattermost --force-new-deployment
   ```
3. **Test OIDC login** on both apps

## What I Originally Thought the Remediation Was

The infrastructure appears correct. The mystery was: **why do test tasks succeed but running services fail?**

Original possible next steps (now superseded by fixes above):
1. **Enable verbose PHP logging in BookStack** - The OIDC failure is silent. BookStack may be caching something or failing for a different reason than network connectivity.
2. **Check actual environment variables in running tasks** - Verify OIDC client ID and secret are being injected correctly (I was unable to retrieve task definitions - they returned empty).
3. **Verify Zitadel OIDC client configuration in Zitadel UI** - Redirect URIs, response types, grant types.
4. **Check if BookStack uses different PHP HTTP client** than curl - May have different TLS or HTTP/2 behavior.
5. **Mattermost: Check System Console > Authentication > GitLab** - The Team Edition uses GitLab OAuth adapter. May need admin UI configuration, not just environment variables.

## Failure Count

**Approximately 20+ failed attempts**, including:
- Initial OIDC configuration without addressing hairpin NAT
- Multiple debugging attempts with curl/nslookup from inside containers
- Session Manager Plugin installation attempts
- ECS Exec attempts (container doesn't have SSM agent)
- run-task with command overrides
- Claiming things were "fixed" without verification (multiple times)
- DNS caching issue (tasks running before DNS change)
- Force redeployments
- Log analysis (no OIDC errors visible)
- Task definition queries returning empty

## How Entrenched We Are

**Deeply entrenched:**

1. **Core infrastructure is complex** - We've built internal ALB, private DNS zone, separate target groups, modified ECS service module for multiple load balancers.

2. **Can't easily test** - No way to interactively debug inside running containers. ECS Exec doesn't work (no SSM agent). Only option is run-task with command override, which proves network works but doesn't explain app behavior.

3. **Silent failures** - No OIDC errors in application logs. The apps just redirect to login without explanation.

4. **Verified working at network layer, failing at app layer** - This suggests the problem is no longer hairpin NAT, but something specific to how BookStack/Mattermost handle OIDC.

5. **Mattermost requires admin UI** - Team Edition may require System Console configuration for GitLab OAuth, not just environment variables.

6. **Multiple moving parts** - Zitadel, three different apps with different OIDC implementations, AWS networking, DNS resolution, Terraform state.

7. **Context window limits** - This conversation has hit context limits and been compacted multiple times, losing detailed debugging history.

## Recommendations for External Support

1. **Access to Zitadel admin UI** - Verify OIDC clients are correctly configured (redirect URIs match exactly, correct grant types)

2. **Manual testing in Zitadel** - Try authenticating directly to Zitadel to confirm it's working

3. **BookStack debug mode** - Enable `APP_DEBUG=true` and check Laravel logs for OIDC-specific errors

4. **Mattermost System Console** - Log in as admin and configure GitLab OAuth through the UI

5. **Consider simpler alternatives** - If OIDC continues failing, consider:
   - Direct Zitadel SAML instead of OIDC
   - LDAP integration
   - Accepting username/password auth temporarily

## Technical Details

### BookStack OIDC Environment Variables (Updated)
```
AUTH_METHOD = "oidc"
OIDC_NAME = "Zitadel"
OIDC_DISPLAY_NAME_CLAIMS = "name"
OIDC_CLIENT_ID = var.oidc_client_id
OIDC_ISSUER = "https://auth.dev.almondbread.org"
OIDC_ISSUER_DISCOVER = "true"
OIDC_USER_TO_GROUPS = "true"
OIDC_GROUPS_CLAIM = "groups"
OIDC_REMOVE_FROM_GROUPS = "true"
OIDC_CLIENT_SECRET = (from Secrets Manager)
APP_PROXIES = "*"  # NEW: Trust ALB proxy headers for HTTPS detection
```

### Mattermost GitLab OAuth Environment Variables (Updated)
```
MM_GITLABSETTINGS_ENABLE = "true"
MM_GITLABSETTINGS_ID = var.oidc_client_id
MM_GITLABSETTINGS_SECRET = (from Secrets Manager)
MM_GITLABSETTINGS_SCOPE = "read_user"  # FIXED: Was "openid profile email"
MM_GITLABSETTINGS_AUTHENDPOINT = "https://auth.dev.almondbread.org/oauth/v2/authorize"
MM_GITLABSETTINGS_TOKENENDPOINT = "https://auth.dev.almondbread.org/oauth/v2/token"
MM_GITLABSETTINGS_USERAPIENDPOINT = "https://auth.dev.almondbread.org/oidc/v1/userinfo"
```

### Test Task Success
```bash
aws ecs run-task \
  --cluster cochlearis-dev-cluster \
  --task-definition cochlearis-dev-zitadel \
  --overrides '{"containerOverrides":[{"name":"zitadel","command":["sh","-c","curl -s https://auth.dev.almondbread.org/.well-known/openid-configuration | head -100"]}]}' \
  --network-configuration "..."
```
This successfully returns the full OIDC discovery JSON.

---

*Document created: 2026-02-01*
*Last updated: 2026-02-01*
*Status: Fixes applied - pending terraform apply and service redeploy*
