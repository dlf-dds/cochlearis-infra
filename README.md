# cochlearis-infra

Infrastructure as code for the **Almondbread Collaboration Services** — a self-hosted platform providing identity management, documentation, and team chat.

> **Note:** This repo deploys to the `cochlearis` AWS account. To adapt for a different account, update the `project` variable and backend configuration in each environment.

---

## What We Deploy

The Almondbread Collaboration Services run across dev, staging, and production environments.

<table>
<tr>
<td width="120" align="center">
<img src="logos/zitadel.png" width="80" alt="Zitadel"/>
<br/><strong>Zitadel</strong>
</td>
<td>
<strong>Identity & Access Management</strong> (Future State)<br/>
Deployed but OIDC integration is WIP. User management, OIDC/OAuth2 provider, MFA support.<br/>
Currently: Google OAuth for BookStack/Zulip, username/password for others.<br/>
<code>auth.{env}.almondbread.org</code>
</td>
</tr>
<tr>
<td align="center">
<img src="logos/bookstack-transp.png" width="80" alt="BookStack"/>
<br/><strong>BookStack</strong>
</td>
<td>
<strong>Documentation Wiki</strong><br/>
Organized documentation with books, chapters, and pages. Markdown support, WYSIWYG editor, full-text search.<br/>
<code>docs.{env}.almondbread.org</code>
</td>
</tr>
<tr>
<td align="center">
<img src="logos/Mattermost.png" width="80" alt="Mattermost"/>
<br/><strong>Mattermost</strong>
</td>
<td>
<strong>Team Chat</strong><br/>
Slack-alternative with channels, direct messages, file sharing, and integrations. ARM64 compatible.<br/>
<code>mm.{env}.almondbread.org</code>
</td>
</tr>
<tr>
<td align="center">
<img src="logos/zulip.png" width="80" alt="Zulip"/>
<br/><strong>Zulip</strong>
</td>
<td>
<strong>Threaded Chat</strong><br/>
Topic-based threading for organized conversations. Better for async communication and searchable history.<br/>
<code>chat.{env}.almondbread.org</code>
</td>
</tr>
<tr>
<td align="center">
<img src="logos/docusaurus.png" width="80" alt="Docusaurus"/>
<br/><strong>Docusaurus</strong>
</td>
<td>
<strong>Developer Documentation</strong><br/>
Static site for technical docs, API references, and guides. No database — just a containerized web server.<br/>
<code>developer.{env}.almondbread.org</code>
</td>
</tr>
<tr>
<td align="center">
<img src="logos/outline.png" width="80" alt="Outline"/>
<br/><strong>Outline</strong>
</td>
<td>
<strong>Knowledge Base</strong><br/>
Modern wiki for team knowledge with real-time collaboration, nested documents, and full-text search.<br/>
<code>wiki.{env}.almondbread.org</code>
</td>
</tr>
</table>

> **Note on Service Overlap:** This platform currently includes overlapping capabilities — two chat services (Mattermost, Zulip) and three documentation tools (BookStack, Docusaurus, Outline). This is intentional during evaluation. We expect to consolidate to one chat service and two documentation tools: one lightweight/fast (Docusaurus for developer docs) and one full-featured (BookStack or Outline for team knowledge). That said, there's a case for keeping specialized tools for distinct use cases.

### Environment URLs

| Service | Dev | Staging | Prod |
|---------|-----|---------|------|
| **Zitadel** (SSO) | auth.dev.almondbread.org | auth.staging.almondbread.org | auth.almondbread.org |
| **BookStack** (Docs) | docs.dev.almondbread.org | docs.staging.almondbread.org | docs.almondbread.org |
| **Mattermost** (Chat) | mm.dev.almondbread.org | mm.staging.almondbread.org | mm.almondbread.org |
| **Zulip** (Chat) | chat.dev.almondbread.org | chat.staging.almondbread.org | chat.almondbread.org |
| **Docusaurus** (Dev Docs) | developer.dev.almondbread.org | developer.staging.almondbread.org | developer.almondbread.org |
| **Outline** (Wiki) | wiki.dev.almondbread.org | wiki.staging.almondbread.org | wiki.almondbread.org |

> **Note on Zulip**: Zulip runs on EC2 (not ECS Fargate) due to architectural constraints with docker-zulip. See [ZULIP.md](docs/ZULIP.md) for details.

**Current Authentication:** Azure AD / Google OAuth for BookStack, Zulip, and Mattermost; **Slack OAuth** for Outline (works with any Slack workspace including free/personal); username/password as fallback where supported. Docusaurus can be protected via ALB-level OIDC authentication (optional). Zitadel SSO is deployed but integration is **on hold** (see [Authentication Status](#authentication-status) below).

### Architecture

```
                                              INTERNET
                                                 |
                                                 v
+=====================================================================================+
|                                   PUBLIC SUBNETS                                    |
|                                                                                     |
|    +----------------------------------------------------------------------------+   |
|    |                     Application Load Balancer (ALB)                        |   |
|    |                          TLS termination (:443)                            |   |
|    |                                                                            |   |
|    |  auth.*    docs.*    mm.*    chat.*    developer.*    wiki.*               |   |
|    |                                          [OIDC Auth]                       |   |
|    +----------------------------------------------------------------------------+   |
|        |          |         |        |            |           |                     |
|        |          |         |        |            | Azure/    |                     |
|        |          |         |        |            | Google    |                     |
+=====================================================================================+
         |          |         |        |            |           |
         v          v         v        v            v           v
+=====================================================================================+
|                                   PRIVATE SUBNETS                                   |
|                                                                                     |
|  +---------+ +---------+ +---------+ +----------+ +---------+ +---------+           |
|  | Zitadel | |BookStack| |Mattermos| |  Zulip   | |Docusaur | | Outline |           |
|  |  :8080  | |   :80   | |  :8065  | | +--+---+ | |   :80   | |  :3000  |           |
|  |         | |         | |         | | |App|PG | | |(static)| |         |           |
|  |         | |         | |         | | |:80|   | | |        | |         |           |
|  +---------+ +---------+ +---------+ | +--+---+ | +---------+ +---------+           |
|       |           |           |      +----------+      |           |                |
|       |           |           |           |            |           |                |
|       v           v           v           v            |           v                |
|  +---------+ +---------+ +---------+ +---------+       |      +---------+           |
|  |   RDS   | |   RDS   | |   RDS   | |   EFS   |  (no db)     |   RDS   |           |
|  |PostgreSQ| |  MySQL  | |PostgreSQ| |(PG data)|              |PostgreSQ|           |
|  +---------+ +---------+ +---------+ +---------+              +---------+           |
|                                                                    |                |
|                          +-------------+                           v                |
|                          | ElastiCache | <-- Zulip          +-------------+         |
|                          |    Redis    |                    | ElastiCache |         |
|                          +-------------+                    |    Redis    |         |
|                                                             +-------------+         |
|                                                                    |                |
|                                                                    v                |
|                                                               +---------+           |
|                                                               |   S3    |           |
|                                                               | Uploads |           |
|                                                               +---------+           |
+=====================================================================================+
```

**Service patterns:**
- **Zitadel, BookStack, Mattermost**: Standard ECS services with managed RDS databases
- **Zulip**: EC2 instance with standard Zulip installation (not ECS — see [ZULIP.md](docs/ZULIP.md))
- **Outline**: Full-featured — RDS PostgreSQL, ElastiCache Redis, S3 for uploads, Slack OAuth
- **Docusaurus**: Stateless — containerized static site with **ALB-level OIDC authentication**

> **Why ECS for Docusaurus?** Static sites are typically deployed via S3 + CloudFront, which is cheaper and simpler for pure static hosting. We chose ECS instead to maintain consistency across all services — everything deploys the same way, tears down the same way, and appears in the same monitoring dashboards. This avoids resource sprawl (orphaned S3 buckets, forgotten CloudFront distributions) and keeps `terraform destroy` predictable.

---

## Authentication & Access Control

Authentication uses two patterns depending on the service type:

| Pattern | Services | How It Works |
|---------|----------|--------------|
| **App-Level OAuth** | BookStack, Zulip, Outline, Mattermost | App handles OAuth flow directly — user clicks "Sign in with Microsoft/Google", app redirects to IdP, receives tokens, creates user session |
| **ALB-Level OIDC** | Docusaurus | ALB intercepts requests and handles OIDC — no app changes needed, just gate access to static content |

**Supported Identity Providers:**
- **Azure AD** (priority) — Works with all services including Mattermost
- **Google OAuth** — Fallback for BookStack, Zulip, Outline (not Mattermost)

**Quick Reference:**

```
Azure AD / Google  ←──  OAuth/OIDC  ──→  ALB  ──→  Apps
     ↑                                    │
     │ User authenticates                 │ ALB OIDC: session cookie (7-day TTL)
     │ once per session                   │ App OAuth: app manages session
     └────────────────────────────────────┘
```

**Enabling authentication:**

```hcl
# environments/aws/dev/terraform.tfvars

# Azure AD (recommended - works with all services)
enable_azure_oauth      = true
azure_tenant_id         = "your-tenant-id"
azure_client_id         = "your-client-id"
azure_client_secret_arn = "arn:aws:secretsmanager:..."

# Optional: Protect Docusaurus with ALB OIDC (uses Azure AD or Google)
enable_docusaurus_auth = true
```

See [Authentication Status](#authentication-status) for detailed setup instructions, redirect URIs, and troubleshooting.

---

**Zulip Sidecar Pattern:** Zulip runs PostgreSQL as a sidecar container within the same ECS task,
persisting data to EFS. This avoids the RDS limitation of one major version upgrade at a time.

**ALB OIDC Authentication (Docusaurus):**

Docusaurus uses ALB-level OIDC authentication instead of app-level auth. This is a simpler pattern for static sites:

```
  Browser                    ALB                   Azure AD/Google         Docusaurus
     |                        |                         |                      |
     |  1. GET /docs          |                         |                      |
     |----------------------->|                         |                      |
     |                        |                         |                      |
     |  2. No session cookie? Redirect to IdP          |                      |
     |<-----------------------|------------------------>|                      |
     |                        |                         |                      |
     |  3. User authenticates with Azure AD/Google     |                      |
     |<------------------------------------------------>|                      |
     |                        |                         |                      |
     |  4. IdP redirects back with auth code           |                      |
     |----------------------->|------------------------>|                      |
     |                        |                         |                      |
     |  5. ALB exchanges code for tokens, sets cookie  |                      |
     |                        |<------------------------|                      |
     |                        |                         |                      |
     |  6. ALB forwards request (user authenticated)   |                      |
     |                        |---------------------------------------->|      |
     |                        |                         |                      |
     |  7. Static content     |<----------------------------------------|      |
     |<-----------------------|                         |                      |
```

> **Why ALB OIDC?** Apps like BookStack and Zulip handle their own OAuth flows because they need user context (permissions, profiles). Docusaurus serves static content and only needs "is this person allowed to view the docs?" — ALB handles this without any app changes.

**OIDC Authentication Flow (On Hold - Reference Only):**

> **Note:** This flow describes the intended Zitadel OIDC integration, which is **on hold**.
> See [Authentication Status](#authentication-status) for current auth methods.

```
  Browser                    ALB                    App               Zitadel
     |                        |                      |                    |
     |  1. GET /login         |                      |                    |
     |----------------------->|--------------------->|                    |
     |                        |                      |                    |
     |  2. Redirect to auth.*/authorize              |                    |
     |<-----------------------|<---------------------|                    |
     |                        |                      |                    |
     |  3. GET /authorize     |                      |                    |
     |----------------------->|------------------------------------------>|
     |                        |                      |                    |
     |  4. Login form         |                      |                    |
     |<-----------------------|<------------------------------------------|
     |                        |                      |                    |
     |  5. POST credentials   |                      |                    |
     |----------------------->|------------------------------------------>|
     |                        |                      |                    |
     |  6. Redirect with auth code to callback       |                    |
     |<-----------------------|<------------------------------------------|
     |                        |                      |                    |
     |  7. GET /callback?code=...                    |                    |
     |----------------------->|--------------------->|                    |
     |                        |                      |                    |
     |                        |  8. Token exchange   |  (via ALB, not     |
     |                        |                      |   direct)          |
     |                        |                      |------------------->|
     |                        |                      |<-------------------|
     |                        |                      |                    |
     |  9. Authenticated!     |                      |                    |
     |<-----------------------|<---------------------|                    |
     |                        |                      |                    |
```

**Important:** Internal OIDC token exchange (step 8) routes through the ALB because apps
resolve Zitadel by its public DNS name (auth.*.almondbread.org). Direct container-to-container
communication isn't possible without custom DNS.

> **Complexity Note:** This architecture required more effort than anticipated. Each service (BookStack, Mattermost, Zulip) has different OIDC configuration requirements, and internal service-to-Zitadel communication must route through the ALB because services resolve Zitadel by its public DNS name. A Kubernetes deployment with internal service discovery (e.g., `zitadel.auth.svc.cluster.local`) would simplify this significantly. If self-hosting at scale, consider EKS or managed Kubernetes over ECS.

---

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.7.0
- [tfenv](https://github.com/tfutils/tfenv) (recommended)
- [direnv](https://direnv.net/)
- [aws-vault](https://github.com/99designs/aws-vault)
- [pre-commit](https://pre-commit.com/)
- [terraform-docs](https://terraform-docs.io/)
- [tflint](https://github.com/terraform-linters/tflint)
- [checkov](https://www.checkov.io/)

## Setup

### 1. Clone the repository

```bash
git clone git@github.com:dlf-dds/cochlearis-infra.git
cd cochlearis-infra
```

### 2. Install pre-commit hooks

```bash
pre-commit install
```

### 3. Allow direnv

```bash
direnv allow
```

### 4. Configure aws-vault

```bash
# Add your AWS credentials (one-time)
aws-vault add cochlearis

# Configure longer session duration (recommended for Terraform applies)
# Add to ~/.aws/config under [profile cochlearis]:
#   [profile cochlearis]
#   region = eu-central-1
#   mfa_serial = arn:aws:iam::ACCOUNT_ID:mfa/USERNAME  # if using MFA
#   credential_process =
#   session_duration = 2h
```

### 5. Bootstrap AWS (first time only)

```bash
# Start aws-vault session with 2-hour duration
aws-vault exec cochlearis --duration=2h

# Run bootstrap
./scripts/bootstrap-aws
```

This creates the S3 bucket and DynamoDB table for Terraform state.

## Usage

### Working with environments

```bash
# Always use aws-vault with extended duration for applies
aws-vault exec cochlearis --duration=2h

cd environments/aws/dev
terraform init
terraform plan
terraform apply  # Can take 15-20 minutes
```

### Formatting

```bash
./scripts/format-files
```

### Generating documentation

```bash
./scripts/update-docs
```

## Directory Structure

```
.
├── .github/workflows/     # GitHub Actions CI/CD
├── environments/          # Environment configurations
│   ├── aws/              # AWS environments
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   ├── gcp/              # GCP environments (future)
│   └── azure/            # Azure environments (future)
├── modules/              # Reusable Terraform modules
│   ├── aws/              # AWS-specific modules
│   ├── gcp/              # GCP-specific modules (future)
│   ├── azure/            # Azure-specific modules (future)
│   └── common/           # Cloud-agnostic modules
└── scripts/              # Utility scripts
```

## Authentication Status

**Current State (2026-02-02):**

| Service | Auth Method | Status |
|---------|-------------|--------|
| **BookStack** | Azure AD / Google OAuth + username/password | Working |
| **Zulip** | Azure AD / Google OAuth + username/password | Working |
| **Outline** | Slack OAuth | Working — any Slack workspace (free/personal) supported |
| **Mattermost** | Azure AD (Office 365) + username/password | Working |
| **Zitadel** | Admin login | Working (IdP deployed, SSO integration **on hold**) |
| **Docusaurus** | ALB OIDC (optional) / None (public) | Working |

> **Note:** Azure AD takes priority over Google OAuth if both are configured. Outline uses Slack OAuth because Google/Azure OAuth require organizational accounts (not personal Gmail/Microsoft). See [GOTCHAS.md](docs/GOTCHAS.md) for details.

> **Docusaurus ALB OIDC:** Unlike other services that handle OAuth themselves, Docusaurus can use ALB-level OIDC authentication. This protects the static site without any app-level changes. Enable with `enable_docusaurus_auth = true` in terraform.tfvars.

**Why Not Zitadel SSO?**

Zitadel OIDC integration was attempted for 48 hours over a full weekend but never worked. Despite solving network-layer issues (hairpin NAT via internal ALB and private DNS), apps still couldn't complete OIDC discovery. We pivoted to Azure AD / Google OAuth.

**Zitadel SSO Status: ON HOLD**

The goal was unified SSO via Zitadel — one login for all services. The infrastructure exists but integration is paused:
- Zitadel is running at `auth.{env}.almondbread.org`
- Internal ALB and private DNS zone exist for service-to-service OIDC
- Bootstrap scripts and separate Terraform root (`dev/oidc/`) are ready
- All OIDC configuration code exists in app modules

To retry Zitadel OIDC later, see [OIDC.md](docs/OIDC.md) for the full troubleshooting history and deployment sequence.

### Enabling Google OAuth (Current Method)

#### Step 1: Create OAuth App in Google Cloud Console

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Navigate to **APIs & Services > OAuth consent screen**
4. Configure the consent screen:
   - User Type: **External** (unless you have Google Workspace)
   - App name: e.g., "Almondbread SSO"
   - User support email: your email
   - Developer contact: your email
5. Add scopes: `email`, `profile`, `openid`
6. Add test users (required for External apps in testing mode)

#### Step 2: Create OAuth Client Credentials

1. Go to **APIs & Services > Credentials**
2. Click **+ CREATE CREDENTIALS > OAuth client ID**
3. Application type: **Web application**
4. Name: e.g., "Almondbread Web Client"
5. **IMPORTANT: Add Authorized redirect URIs** (each as a SEPARATE entry, not comma-separated!)
   Click **+ ADD URI** for each:
   - `https://docs.dev.almondbread.org/login/service/google/callback` (BookStack)
   - `https://chat.dev.almondbread.org/complete/google/` (Zulip)
   - `https://wiki.dev.almondbread.org/auth/google.callback` (Outline)
6. Click **CREATE**
7. Copy the **Client ID** and **Client Secret**

> **Common Error:** If you enter redirect URIs as a comma-separated string, Google will treat it as a single invalid URI. Each URI must be added separately using the "+ ADD URI" button.

#### Step 3: Store Client Secret in AWS Secrets Manager

```bash
aws-vault exec cochlearis --no-session -- aws secretsmanager create-secret \
  --name cochlearis-dev-google-oauth \
  --secret-string '{"client_secret":"YOUR_SECRET_HERE"}' \
  --region eu-central-1
```

Note the ARN returned (e.g., `arn:aws:secretsmanager:eu-central-1:891377314745:secret:cochlearis-dev-google-oauth-SUFFIX`).

#### Step 4: Update Terraform Configuration

Edit `environments/aws/dev/terraform.tfvars`:
```hcl
enable_google_oauth     = true
google_oauth_client_id  = "YOUR_CLIENT_ID.apps.googleusercontent.com"
google_oauth_secret_arn = "arn:aws:secretsmanager:eu-central-1:ACCOUNT:secret:cochlearis-dev-google-oauth-SUFFIX"
```

#### Step 5: Apply and Force Redeploy

```bash
cd environments/aws/dev

# Apply Terraform changes
aws-vault exec cochlearis --no-session -- terraform apply

# Force ECS services to pick up new task definitions
# (Terraform changes task definitions but ECS may keep running old containers)
aws-vault exec cochlearis --no-session -- \
  aws ecs update-service --cluster cochlearis-dev --service cochlearis-dev-bookstack --force-new-deployment --region eu-central-1

aws-vault exec cochlearis --no-session -- \
  aws ecs update-service --cluster cochlearis-dev --service cochlearis-dev-zulip --force-new-deployment --region eu-central-1

aws-vault exec cochlearis --no-session -- \
  aws ecs update-service --cluster cochlearis-dev --service cochlearis-dev-outline --force-new-deployment --region eu-central-1
```

#### Step 6: Wait for Deployment

New containers need time to start (~2-5 minutes). Check status:
```bash
aws-vault exec cochlearis --no-session -- \
  aws ecs describe-services --cluster cochlearis-dev \
  --services cochlearis-dev-bookstack cochlearis-dev-zulip cochlearis-dev-outline \
  --query 'services[].{name:serviceName,running:runningCount,desired:desiredCount,deployments:length(deployments)}' \
  --output table --region eu-central-1
```

#### Troubleshooting Google OAuth

| Error | Cause | Solution |
|-------|-------|----------|
| `redirect_uri_mismatch` | URI not registered in Google Console | Add exact URI to Authorized redirect URIs (each as separate entry) |
| "This Google account is not linked" | Auto-registration disabled | Ensure `GOOGLE_AUTO_REGISTER=true` in app config |
| Old login page showing | Old container still running | Force redeploy with `aws ecs update-service --force-new-deployment` |
| "Access blocked: app request is invalid" | OAuth consent screen not configured | Complete consent screen setup with test users |

#### Supported Services

| Service | Redirect URI | Notes |
|---------|-------------|-------|
| BookStack | `/login/service/google/callback` | Uses standard + social providers, auto-registration enabled |
| Zulip | `/complete/google/` | Uses python-social-auth, also allows email/password |
| Outline | `/auth/google.callback` | Requires at least one auth provider |
| Mattermost | N/A | Google OAuth not supported; use Azure AD instead |
| Docusaurus | N/A | Public site, no auth required |

#### First-Time Zulip Setup: Creating an Organization

**Important**: Zulip is organization-based. Before anyone can sign in, you must create an organization first.

1. **Visit the new organization page**:
   ```
   https://chat.dev.almondbread.org/new/
   ```

2. **Fill in organization details**:
   - Organization type (e.g., "Corporate")
   - Organization name (e.g., "Almondbread")
   - Your email and name

3. **Complete registration** - You'll become the organization **admin**

**Note**: The "Don't have an account?" link on the login page only becomes active after an organization exists. Until then, users cannot self-register even with Google/Azure OAuth configured.

**For production** (recommended):
- Set `SETTING_OPEN_REALM_CREATION = "False"` in the Zulip module
- Generate realm creation links via ECS exec:
  ```bash
  aws-vault exec cochlearis --no-session -- aws ecs execute-command \
    --region eu-central-1 \
    --cluster cochlearis-dev-cluster \
    --task <task-arn> \
    --container zulip \
    --interactive \
    --command "/home/zulip/deployments/current/manage.py generate_realm_creation_link"
  ```

**Troubleshooting**: If you get "Internal server error" when submitting the organization creation form, email is likely misconfigured. Zulip requires working email to send confirmation messages. Ensure the Zulip module has `SECRETS_email_host_user` and `SECRETS_email_host_password` configured (see [GOTCHAS.md](docs/GOTCHAS.md) for details).

### Enabling Slack OAuth for Outline

**Important**: Outline requires an OAuth provider (it does NOT support email/password login). While Google and Azure AD OAuth are listed above, they only work with **organizational accounts** (Google Workspace, Azure AD). For personal Gmail/Microsoft accounts, use **Slack OAuth** instead.

Slack OAuth works with **any Slack workspace** including free/personal workspaces.

#### Step 1: Create Slack App

1. Go to [Slack API](https://api.slack.com/apps) > **Create New App** > **From scratch**
2. Name: e.g., "Outline Wiki"
3. Select your Slack workspace

#### Step 2: Configure OAuth & Permissions

1. Go to **OAuth & Permissions** in the left sidebar
2. Under **Redirect URLs**, add:
   ```
   https://wiki.dev.almondbread.org/auth/slack.callback
   ```
3. Under **Scopes** > **User Token Scopes**, add:
   - `identity.avatar`
   - `identity.basic`
   - `identity.email`
   - `identity.team`

#### Step 3: Get Credentials

1. Go to **Basic Information**
2. Copy **Client ID** and **Client Secret**

#### Step 4: Store Secret in AWS Secrets Manager

```bash
aws-vault exec cochlearis --no-session -- aws secretsmanager create-secret \
  --name cochlearis-dev-outline-slack-oauth \
  --secret-string '{"client_secret":"YOUR_SECRET_HERE"}' \
  --region eu-central-1
```

#### Step 5: Update Terraform Configuration

Edit `environments/aws/dev/terraform.tfvars`:
```hcl
outline_slack_client_id  = "YOUR_CLIENT_ID"
outline_slack_secret_arn = "arn:aws:secretsmanager:eu-central-1:ACCOUNT:secret:cochlearis-dev-outline-slack-oauth-SUFFIX"
```

#### Step 6: Apply and Redeploy

```bash
aws-vault exec cochlearis --no-session -- terraform apply
```

ECS will automatically deploy new Outline containers with Slack OAuth configured.

### Enabling Azure AD OAuth

Azure AD (Microsoft) OAuth works with all services including Mattermost. It takes priority over Google OAuth if both are configured.

#### Step 1: Create Azure AD App Registration

1. Go to [Azure Portal](https://portal.azure.com/) > **Azure Active Directory** > **App registrations**
2. Click **New registration**
3. Configure:
   - Name: e.g., "Almondbread SSO"
   - Supported account types: **Accounts in this organizational directory only** (single tenant) or **Accounts in any organizational directory** (multi-tenant)
   - Redirect URIs: Add as **Web** platform (each as separate entry):
     - `https://docs.dev.almondbread.org/login/service/azure/callback` (BookStack)
     - `https://chat.dev.almondbread.org/complete/azuread-oauth2/` (Zulip)
     - `https://wiki.dev.almondbread.org/auth/azure.callback` (Outline)
     - `https://mm.dev.almondbread.org/signup/office365/complete` (Mattermost)
4. Click **Register**
5. Note the **Application (client) ID** and **Directory (tenant) ID**

#### Step 2: Create Client Secret

1. In your app registration, go to **Certificates & secrets**
2. Click **New client secret**
3. Add description (e.g., "Terraform") and expiration
4. Copy the secret **Value** immediately (it won't be shown again)

#### Step 3: Configure API Permissions

1. Go to **API permissions**
2. Click **Add a permission** > **Microsoft Graph** > **Delegated permissions**
3. Add: `email`, `openid`, `profile`, `User.Read`
4. Click **Grant admin consent** (if you have admin rights)

#### Step 4: Store Client Secret in AWS Secrets Manager

```bash
aws-vault exec cochlearis --no-session -- aws secretsmanager create-secret \
  --name cochlearis-dev-azure-oauth \
  --secret-string '{"client_secret":"YOUR_CLIENT_SECRET"}' \
  --region eu-central-1
```

#### Step 5: Update Terraform Configuration

Edit `environments/aws/dev/terraform.tfvars`:
```hcl
enable_azure_oauth      = true
azure_tenant_id         = "YOUR_TENANT_ID"
azure_client_id         = "YOUR_CLIENT_ID"
azure_client_secret_arn = "arn:aws:secretsmanager:eu-central-1:ACCOUNT:secret:cochlearis-dev-azure-oauth-SUFFIX"
```

#### Step 6: Apply and Force Redeploy

```bash
cd environments/aws/dev
aws-vault exec cochlearis --no-session -- terraform apply

# Force redeploy all services
for svc in bookstack zulip outline mattermost; do
  aws-vault exec cochlearis --no-session -- \
    aws ecs update-service --cluster cochlearis-dev-cluster --service $svc --force-new-deployment --region eu-central-1
done
```

#### Azure AD Redirect URIs

| Service | Redirect URI |
|---------|-------------|
| BookStack | `/login/service/azure/callback` |
| Zulip | `/complete/azuread-oauth2/` |
| Outline | `/auth/azure.callback` |
| Mattermost | `/signup/office365/complete` |

### Enabling Zitadel SSO (On Hold)

> **Warning:** This was attempted for 48 hours without success. Integration is on hold.

See [DEPLOY.md](docs/DEPLOY.md) for the full sequence:
1. Deploy with `enable_zitadel_oidc = false`
2. Wait for Zitadel health
3. Create PAT manually in Zitadel console
4. Run bootstrap script
5. Deploy OIDC root (`dev/oidc/`)
6. Enable OIDC and redeploy

See [GOTCHAS.md](docs/GOTCHAS.md) and [OIDC.md](docs/OIDC.md) for troubleshooting.

## CI/CD

This repository uses GitHub Actions for CI/CD:

- **terraform-validate.yml**: Runs on all PRs - validates formatting, syntax, and linting
- **terraform-plan.yml**: Runs on PRs to main - generates and posts Terraform plan
- **terraform-apply.yml**: Runs on merge to main - applies changes (prod requires approval)

## Contributing

1. Create a feature branch
2. Make changes
3. Run `pre-commit run --all-files`
4. Open a pull request

---

## Infrastructure Governance

This repository implements a governance framework that should be used as a template for all infrastructure projects. The framework ensures cost control, resource lifecycle management, and operational visibility.

### Tagging Strategy

All resources receive default tags via the AWS provider configuration. These tags are **mandatory** for all infrastructure:

| Tag | Purpose | Example Values |
|-----|---------|----------------|
| `Project` | Groups resources for cost allocation and lifecycle | `cochlearis` |
| `Environment` | Identifies deployment stage | `dev`, `staging`, `prod` |
| `Owner` | Contact email for alerts and accountability | `team@example.com` |
| `ManagedBy` | Tracks how resource was created | `terraform` |
| `Lifecycle` | Controls automatic lifecycle management | `persistent`, `temporary` |
| `Repository` | Links resource to source code | `cochlearis-infra` |

**Optional tags for lifecycle control:**

| Tag | Purpose | Format |
|-----|---------|--------|
| `ExpiresAt` | Explicit expiration date | ISO 8601: `2025-03-01T00:00:00Z` |
| `CreatedAt` | Creation timestamp (for age-based expiry) | ISO 8601: `2025-01-15T12:00:00Z` |

### Resource Lifecycle Management

Resources are managed based on their `Lifecycle` tag:

**`Lifecycle: persistent`** (default)
- Resource lives indefinitely
- No automatic warnings or termination
- Use for production databases, core networking, etc.

**`Lifecycle: temporary`**
- Resource is subject to automatic lifecycle enforcement
- Warning email sent after 30 days
- Auto-terminated after 60 days (if enabled)
- Use for dev/test resources, experiments, demos

**Extending temporary resources:**
```bash
# Option 1: Set explicit expiration date
aws ec2 create-tags --resources i-1234567890abcdef0 \
  --tags Key=ExpiresAt,Value=2025-04-01T00:00:00Z

# Option 2: Convert to persistent
aws ec2 create-tags --resources i-1234567890abcdef0 \
  --tags Key=Lifecycle,Value=persistent
```

### Cost Management

The governance module provides:

1. **Monthly budget alerts** - Notifications at 50%, 80%, 100%, 120% of budget
2. **Weekly cost reports** - Emailed every Monday with spend breakdown by service
3. **Cost forecasting** - Projected monthly spend based on current usage

Configure in `terraform.tfvars`:
```hcl
monthly_budget_limit    = 200   # USD
owner_email            = "team@example.com"
enable_auto_termination = true  # Set false to only alert, not terminate
```

### Applying to New Projects

When creating new infrastructure projects, follow this pattern:

1. **Copy the governance module** to your project's `modules/` directory

2. **Configure provider default tags** in each environment:
   ```hcl
   provider "aws" {
     default_tags {
       tags = {
         Project     = var.project
         Environment = var.environment
         Owner       = var.owner_email
         ManagedBy   = "terraform"
         Lifecycle   = "persistent"
       }
     }
   }
   ```

3. **Include the governance module** in each environment:
   ```hcl
   module "governance" {
     source = "../../../modules/aws/governance"

     project                    = var.project
     environment                = var.environment
     owner_email                = var.owner_email
     monthly_budget_limit       = var.monthly_budget_limit
     enable_auto_termination    = var.enable_auto_termination
   }
   ```

4. **Override lifecycle for temporary resources**:
   ```hcl
   resource "aws_instance" "experiment" {
     # ...
     tags = {
       Lifecycle = "temporary"
       ExpiresAt = "2025-03-01T00:00:00Z"
     }
   }
   ```

### Environment-Specific Recommendations

| Environment | `Lifecycle` Default | Auto-Terminate | Budget |
|-------------|---------------------|----------------|--------|
| dev | `temporary` | Yes | Low ($50-200) |
| staging | `persistent` | No | Medium ($200-500) |
| prod | `persistent` | No | As needed |

### Alerts and Notifications

All governance alerts are sent via SNS to the configured `owner_email`. Alert types:

- **Budget threshold reached** - Immediate notification
- **Resource expiring soon** - 30 days before expiration
- **Resource expired** - Requires action or will be terminated
- **Weekly summary** - Cost report and resource status

To add additional subscribers:
```hcl
resource "aws_sns_topic_subscription" "additional" {
  topic_arn = module.governance.sns_topic_arn
  protocol  = "email"
  endpoint  = "additional@example.com"
}
```

---

## Addendum: Multi-Cloud Identity Access Patterns

Secure credential management for each cloud provider without storing long-lived secrets.

### AWS

Use [aws-vault](https://github.com/99designs/aws-vault) for secure credential management with STS temporary tokens:

```bash
# Add credentials to secure keychain (one-time)
aws-vault add cochlearis

# Execute commands with temporary credentials (use --duration for long operations)
aws-vault exec cochlearis --duration=2h -- terraform apply

# Or start a subshell with extended duration
aws-vault exec cochlearis --duration=2h
```

**IAM operations and `--no-session`**: If you encounter `InvalidClientTokenId` errors when creating IAM roles, users, or policies, use the `--no-session` flag:

```bash
# Use --no-session for Terraform operations that create IAM resources
aws-vault exec cochlearis --no-session -- terraform apply
```

This bypasses STS session tokens and uses raw IAM credentials directly. The issue occurs because aws-vault generates session tokens via regional STS endpoints, but IAM is a global service that sometimes rejects these regional tokens. The `--no-session` flag avoids this by using your IAM credentials without wrapping them in an STS session.

**For CI/CD**: Use OIDC with IAM roles (no secrets stored):

```yaml
# GitHub Actions example
permissions:
  id-token: write
steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::123456789:role/github-actions
      aws-region: eu-central-1
```

### GCP

Use `gcloud` CLI with Application Default Credentials (ADC) - no additional tools needed:

```bash
# Login once (opens browser, caches credentials securely)
gcloud auth application-default login

# Set default project
gcloud config set project my-project

# Terraform/SDK automatically uses these credentials
terraform plan
```

**For service account impersonation** (recommended for elevated privileges):

```bash
gcloud auth application-default login \
  --impersonate-service-account=terraform@project.iam.gserviceaccount.com
```

**For CI/CD**: Use Workload Identity Federation (keyless auth):

```yaml
# GitHub Actions example
- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: projects/123/locations/global/workloadIdentityPools/github/providers/github
    service_account: terraform@project.iam.gserviceaccount.com
```

### Azure

Use `az` CLI with built-in credential caching:

```bash
# Login once (opens browser, caches credentials securely)
az login

# Set default subscription
az account set --subscription "My Subscription"

# Terraform/SDK automatically uses these credentials
terraform plan
```

**For service principal impersonation**:

```bash
az login --service-principal \
  --username $ARM_CLIENT_ID \
  --password $ARM_CLIENT_SECRET \
  --tenant $ARM_TENANT_ID
```

**For CI/CD**: Use OIDC with Service Principal (no secrets stored):

```yaml
# GitHub Actions example
- uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

### Comparison

| Feature | AWS | GCP | Azure |
|---------|-----|-----|-------|
| CLI tool | aws-vault | gcloud | az |
| Credential storage | OS keychain | OS keyring | OS keyring |
| Session duration | 1-12 hours (configurable) | 1 hour (auto-refresh) | 1 hour (auto-refresh) |
| MFA support | Yes (via STS) | Yes (via gcloud) | Yes (via az) |
| Keyless CI/CD | OIDC + IAM roles | Workload Identity Federation | OIDC + Service Principal |

### Best Practices

1. **Never store long-lived credentials** - Use temporary tokens and OIDC where possible
2. **Use least privilege** - Create dedicated roles/service accounts for Terraform
3. **Enable MFA** - Require MFA for interactive sessions
4. **Audit access** - Enable CloudTrail (AWS), Cloud Audit Logs (GCP), or Activity Log (Azure)
5. **Rotate credentials** - If using service account keys, rotate them regularly
