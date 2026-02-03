## Context

We are trying to deploy Zitadel v4, Mattermost Team Edition, BookStack, and Zulip on AWS ECS Fargate with OIDC integration. However, we are stuck in a "Fix Loop Hell" where attempts to fix one issue lead to new problems, creating a cycle of failures.

We are less interested in getting these apps working perfectly and more concerned with getting them sufficiently functional in order to move on to other priorities. The goal is to break the cycle of endless fixes and reach a stable state.



### Major Issues of Functionality"

The primary reason you were caught in "Fix Loop Hell" is that **Claude Code (and most LLMs) treat these apps as "Standard Web Apps."** In reality:

* **Zitadel v4** is a breaking-change architecture (UI split).
* **Zulip** is a Python monolith with fragile database-wait loops.
* **Mattermost Team** is "OIDC-lite" (faking it via GitLab).
* **AWS ECS** is a black box that hides networking failures until the task is already dead.

---

### The "Anatomy of the Failure" (Root Causes)

#### 1. The Hairpin NAT "Ghost"

This was your biggest obstacle. Most LLMs assume that if `https://auth...` works from your laptop, it works from the VPC. They don't account for the fact that Fargate tasks in private subnets literally cannot "see" their own public ALB IP without the specific Internal ALB/Private DNS bypass you engineered. This is a 400-level networking problem.

#### 2. The Persistence Mismatch

You were fighting **Stateless vs. Stateful** expectations:

* **Zitadel** expects to be an "Instance," but ECS treats it as a "Task."
* When you changed environment variables (like `FIRSTINSTANCE`), Zitadel ignored them because the RDS database was already "poisoned" by the previous failed attempt. In an LLM fix-loop, the LLM just keeps changing the variables, not realizing the **database state** is what needs to be wiped.

#### 3. The "Team Edition" Trap

Mattermost Team Edition is "OIDC-hostile." It doesn't want you to use OIDC; it wants you to pay for Enterprise. Forcing it through the "GitLab Adapter" is a hack that requires perfect `read_user` scope alignment—something standard OIDC instructions won't tell you.

---

### Strategy to Break the Loop (The Monday Morning Plan)

#### Step 1: The "Zitadel" Hard Reset

Since `ZITADEL_FIRSTINSTANCE` variables are ignored after the first run, your Zitadel config is likely a "Frankenstein" of multiple failed attempts.

* **Remediation:** Drop the Zitadel schema in your RDS (or delete the RDS/sidecar volume) and redeploy with `ZITADEL_DEFAULTINSTANCE_FEATURES_LOGINV2_REQUIRED=false` set from **second zero**. This is the only way to get the "Legacy UI" back in v4.

#### Step 2: BookStack "Trust"

Your BookStack 302 redirect is a **Proxy Trust** issue.

* **Remediation:** Add `APP_PROXIES="*"` immediately. Without this, BookStack thinks it's being accessed via insecure `http` (from the ALB) and refuses to initiate the OIDC handshake over what it perceives as an insecure connection.

#### Step 3: Mattermost "Scope"

The invisible button is almost certainly the `read_user` scope.

* **Remediation:** Change `MM_GITLABSETTINGS_SCOPE` from `openid profile email` to strictly `read_user`. The GitLab adapter inside Mattermost looks for that specific string to enable the UI element.

---

### Final Advice: Stop "Polishing" the Infrastructure

You have a 2-week engineering sprint for a Theater-Wide Data Fabric (Zenoh/OpenZiti). **The infrastructure you've built is now "Good Enough."**

1. **Stop trying to automate the "last 5%."** If a setting in Zitadel needs a manual click in the Console to enable a grant type, **just click it.** 2.  **Accept the "Manual PAT" step.** It takes 30 seconds to create a Personal Access Token in the UI, but it can take 4 hours to automate it via Terraform.
2. **Use the "Almond Bread" Code Name:** You have a domain and a brand. Use that to unify the team.

## CONTEXT to grab when restarting:
for aws perms run this preface:
```bash
aws-vault exec cochlearis --no-session -- <cmd>
```

---

## Architecture Patterns

### Module Structure
All apps follow a consistent pattern in `modules/aws/apps/<app-name>/`:
- `main.tf` - Core resources (RDS/Redis/S3, ECS service, ALB routing)
- `variables.tf` - Standard inputs (project, environment, vpc, alb, ecs) + app-specific
- `outputs.tf` - url, domain, db_endpoint, etc.

New apps should copy an existing pattern:
- **With RDS only**: Use `bookstack` or `mattermost` as template
- **With RDS + Redis + S3**: Use `outline` as template
- **Stateless**: Use `docusaurus` as template
- **Sidecar PostgreSQL**: Use `zulip` (EFS-backed, avoids RDS upgrade pain)

### Authentication Strategy

**Status (2026-02-02)**: Zitadel OIDC **ON HOLD** after 48 hours of troubleshooting.

**Current approach**:
- **Azure AD / Google OAuth**: Primary SSO for BookStack, Zulip, Mattermost
- **Slack OAuth**: Primary auth for Outline (works with any Slack workspace including free/personal)
- **Username/Password**: Fallback for apps that support it

**Why Zitadel is on hold**:
- 48 hours of debugging with no successful OIDC redirect
- Hairpin NAT "solved" at network layer but apps still couldn't discover OIDC
- Event deadline required functional services over perfect IdP
- May revisit self-hosted IdP (Zitadel, Keycloak, Authentik) when time permits

**To pick up Zitadel later**:
1. Read `OIDC.md` for full history
2. Consider fresh RDS + Zitadel v3 (simpler than v4)
3. Test OIDC discovery from inside VPC (ECS task), not just externally
4. See `GOTCHAS.md` "Zitadel OIDC: Abandoned After 48 Hours"

**Legacy OIDC infrastructure** (still exists but unused):
- Separate Terraform root: `environments/aws/dev/oidc/`
- Bootstrap scripts: `bootstrap-zitadel-oidc.sh`, `list-zitadel-resources.sh`
- SSM parameters: `/${project}/${environment}/oidc/<app>/client-id`

### ECS Security Group Ports
ALB ingress ports are managed centrally in the ECS module call:
```hcl
alb_ingress_ports = [80, 3000, 8065, 8080]
# 80: Zulip/BookStack/Docusaurus
# 3000: Outline
# 8065: Mattermost
# 8080: Zitadel
```
When adding a new app on a different port, update this list.

### Service Overlap (Intentional)
The platform has redundant services during evaluation:
- **Chat**: Mattermost, Zulip (will consolidate to one)
- **Docs**: BookStack, Docusaurus, Outline (will keep two: one fast, one full-featured)

## Key Files
- `environments/aws/dev/main.tf` - All module wiring for dev
- `modules/aws/ecs-service/` - Shared ECS task/service module
- `modules/aws/zitadel-oidc/` - Creates OIDC apps in Zitadel + stores secrets
- `README.md` - Architecture diagrams, setup instructions
- `GOTCHAS.md` - Troubleshooting specific issues

## Don't Guess, Read
Before documenting or modifying an app, read its actual module implementation. Don't assume S3+CloudFront for static sites or standard OIDC flows.


