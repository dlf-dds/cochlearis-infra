# Deployment Gotchas

Lessons learned from deploying services to ECS Fargate.

## AWS / Terraform

### AWS CLI Region
Always specify `--region eu-central-1` when using AWS CLI, or it may fail to find resources.

### AWS Vault Authentication
Use `aws-vault exec cochlearis --no-session --` for AWS authentication, not standard AWS CLI profile switching.

### Terraform State
When checking resources, the cluster name from state is `cochlearis-dev-cluster`, not `cochlearis-dev`.

## Zitadel

### Admin Login Username Format
**Problem**: Logging in with just `admin` returns "User could not be found".

**Cause**: Zitadel usernames include the organization domain. The format is `{username}@zitadel.{external-domain}`.

**Solution**: Use the full username format:
```
admin@zitadel.auth.dev.almondbread.org
```

The password is stored in Secrets Manager:
```bash
aws-vault exec cochlearis --no-session -- aws secretsmanager get-secret-value \
    --secret-id cochlearis-dev-zitadel-master-key \
    --region eu-central-1 \
    --query 'SecretString' \
    --output text | jq -r '.admin_password'
```

**Finding the actual username**: If unsure, query the database:
```sql
SELECT * FROM projections.login_names3_users;
```

See [GitHub Discussion #8553](https://github.com/zitadel/zitadel/discussions/8553) for more details.

### FIRSTINSTANCE Variables Only Work on Initial Setup
**Problem**: Environment variables like `ZITADEL_FIRSTINSTANCE_ORG_HUMAN_USERNAME` are ignored.

**Cause**: `ZITADEL_FIRSTINSTANCE_*` and `ZITADEL_DEFAULTINSTANCE_*` variables only take effect during the **first database initialization**. If the database already has data, these settings are ignored.

**Solution**: To change these settings, you must delete the database and let Zitadel recreate it fresh.

### v4 Login UI Architecture Change
**Problem**: Zitadel v4+ returns `{"code":5, "message":"Not Found"}` in the browser for `/ui/login` and `/ui/console` paths. The page may briefly flash the UI before showing the error.

**Cause**: In Zitadel v4, the Login UI was split into a separate Next.js application that needs to be deployed and configured separately. The main Go binary no longer bundles the Login UI by default. The redirect goes to `/ui/v2/login/login?authRequest=...` which doesn't exist.

**Critical**: According to [GitHub Issue #10405](https://github.com/zitadel/zitadel/issues/10405), environment variables like `ZITADEL_DEFAULTINSTANCE_FEATURES_LOGINV2_REQUIRED=false` **only work during initial setup**. They don't affect existing installations.

**Solutions for existing installations**:
1. **Delete the database** and let Zitadel create a fresh instance with the correct settings
2. **Use Zitadel v3.x** instead of v4.x (simpler self-hosted deployments)
3. **Deploy the separate Login UI container** (see [ZITADEL docs](https://zitadel.com/docs/self-hosting/manage/login-client))
4. **Use the API/Console** to disable Login V2 at the instance level (if you can access it)

### Password Grant Type Disabled by Default
**Problem**: Authenticating to Zitadel API with username/password returns `{"error":"unsupported_grant_type","error_description":"password not supported"}`.

**Cause**: Zitadel disables the Resource Owner Password Credentials (ROPC) grant type by default for security reasons.

**Solution**: Use a Personal Access Token (PAT) instead - see "Creating a Personal Access Token" below.

### Creating a Personal Access Token (PAT) - Required Manual Step
**⚠️ This is the ONE manual step required for SSO automation.**

PATs in Zitadel are **only available for service/machine users**, not human users. You must create a service user first.

1. Log into Zitadel console: `https://auth.dev.almondbread.org/ui/console`
2. Username: `admin@zitadel.auth.dev.almondbread.org`
3. Get password from Secrets Manager:
   ```bash
   aws-vault exec cochlearis --no-session -- aws secretsmanager get-secret-value \
     --secret-id cochlearis-dev-zitadel-master-key --region eu-central-1 \
     --query 'SecretString' --output text | jq -r '.admin_password'
   ```
4. **Create a Service User:**
   - Left sidebar → Select your organization (e.g., "ZITADEL")
   - Click **"Service Users"** (or "Users" and filter by machine type)
   - Click **"+New"** to create a service user
   - Name it something like "terraform-bootstrap"
   - Grant it **ORG_OWNER** role (in the user's Authorizations tab)

5. **Create PAT for the Service User:**
   - Click on the service user you just created
   - Scroll down to **"Personal Access Tokens"** section
   - Click **"+New"**
   - Set expiration (optional) and click "Add"
   - **Copy the token immediately** (you won't see it again)

Use the token with the bootstrap script:
```bash
ZITADEL_PAT="your-token-here" ./bootstrap-zitadel-oidc.sh
```

Reference: [Zitadel PAT Documentation](https://zitadel.com/docs/guides/integrate/service-users/personal-access-token)

### Enabling SSO for BookStack, Zulip, and Mattermost
**Goal**: Configure OIDC single sign-on via Zitadel for all applications.

**Prerequisites**: Zitadel must be running and accessible at `https://auth.dev.almondbread.org`.

**Steps**:
1. Run the bootstrap script to create a Zitadel service account:
   ```bash
   cd environments/aws/dev
   ./bootstrap-zitadel-oidc.sh
   ```
   This script:
   - Authenticates to Zitadel as admin
   - Creates a `terraform-oidc` service account with IAM_OWNER permissions
   - Generates a JWT key and stores it in Secrets Manager
   - Stores the organization ID in SSM Parameter Store

2. Enable OIDC in Terraform and apply:
   ```bash
   # In terraform.tfvars or via command line
   enable_zitadel_oidc = true

   terraform apply
   ```

Terraform will automatically:
- Read the organization ID from SSM Parameter Store
- Create OIDC applications in Zitadel for BookStack, Zulip, and Mattermost
- Store client credentials in Secrets Manager
- Redeploy ECS services with OIDC configuration

**No manual copy-paste required** - the automation handles all credential passing.

## Mattermost Configuration

### Team Edition Uses GitLab-Style OAuth
**Context**: Mattermost Team Edition (free) doesn't have native OpenID Connect support - that requires Professional/Enterprise editions.

**Solution**: Mattermost's GitLab SSO integration can be configured to work with any OAuth 2.0/OIDC provider by customizing the endpoints:
```hcl
MM_GITLABSETTINGS_ENABLE          = "true"
MM_GITLABSETTINGS_ID              = "client_id"
MM_GITLABSETTINGS_SECRET          = "client_secret"
MM_GITLABSETTINGS_SCOPE           = "openid profile email"
MM_GITLABSETTINGS_AUTHENDPOINT    = "https://auth.dev.almondbread.org/oauth/v2/authorize"
MM_GITLABSETTINGS_TOKENENDPOINT   = "https://auth.dev.almondbread.org/oauth/v2/token"
MM_GITLABSETTINGS_USERAPIENDPOINT = "https://auth.dev.almondbread.org/oidc/v1/userinfo"
```

The callback URL for Mattermost is `/signup/gitlab/complete` (not a standard OIDC callback).

### Mattermost "Not Secure" Browser Warning Behind ALB
**Problem**: Chrome shows red "Not Secure" warning for Mattermost even though the SSL certificate is valid. Clicking the warning shows "Your connection to this site is not secure" but also "Certificate is valid".

**Cause**: Mattermost doesn't know it's behind a TLS-terminating load balancer. When ALB forwards HTTP requests to the container, Mattermost may generate internal URLs (especially WebSocket URLs) using HTTP instead of HTTPS. Chrome detects this mixed-security state and shows the warning.

**Solution**: Add explicit WebSocket URL and proxy trust settings:
```hcl
environment_variables = {
  MM_SERVICESETTINGS_SITEURL       = "https://${local.domain}"
  MM_SERVICESETTINGS_WEBSOCKETURL  = "wss://${local.domain}/api/v4/websocket"
  MM_SERVICESETTINGS_TRUSTEDPROXYIPHEADER = "X-Forwarded-For"
  # ... other settings
}
```

**Key settings**:
- `MM_SERVICESETTINGS_WEBSOCKETURL`: Explicitly set WSS URL instead of letting Mattermost derive it
- `MM_SERVICESETTINGS_TRUSTEDPROXYIPHEADER`: Trust the `X-Forwarded-For` header from ALB

**After applying**: Force redeploy to pick up new environment variables:
```bash
aws ecs update-service --cluster CLUSTER --service mattermost --force-new-deployment
```

### Mattermost Domain Separate from Zulip
**Context**: When evaluating Zulip and Mattermost in parallel, they need different subdomains.

**Configuration**:
- Zulip: `chat.dev.almondbread.org`
- Mattermost: `mm.dev.almondbread.org`

The Mattermost module uses a `subdomain` variable (default: "mm") to avoid conflicts.

## Zulip Configuration

### Organization Creation Requires Link by Default
**Problem**: Visiting Zulip shows "There is no Zulip organization at this URL" and creating an organization requires an "organization creation link".

**Cause**: By default, Zulip restricts organization creation to users with a valid creation link (for security on public instances).

**Solution**: For dev environments, enable open realm creation:
```hcl
SETTING_OPEN_REALM_CREATION = "True"
```

Then visit `https://chat.dev.almondbread.org/new/` to create an organization.

**Note**: Disable this in production and use creation links instead.

### Zulip Requires Organization Creation Before User Signup
**Problem**: After deploying Zulip, the "Don't have an account?" text on the login page isn't clickable, and Google/Azure sign-in shows "This account does not have access to any organizations."

**Cause**: Zulip is organization-based. Unlike other apps where anyone can sign up, Zulip requires at least one organization to exist before users can register. The "Don't have an account?" link only becomes active when there's an organization to join.

**Solution**: Create an organization first by visiting:
```
https://chat.{env}.almondbread.org/new/
```

This is enabled by `SETTING_OPEN_REALM_CREATION = "True"` in the Zulip module. The person who creates the organization becomes the **admin**.

**Alternative (via ECS Exec)**: Generate a one-time realm creation link:
```bash
aws-vault exec cochlearis --no-session -- aws ecs execute-command \
  --region eu-central-1 \
  --cluster cochlearis-dev-cluster \
  --task $(aws-vault exec cochlearis --no-session -- aws ecs list-tasks --region eu-central-1 --cluster cochlearis-dev-cluster --service-name zulip --query 'taskArns[0]' --output text | xargs basename) \
  --container zulip \
  --interactive \
  --command "/home/zulip/deployments/current/manage.py generate_realm_creation_link"
```

**Note**: For production, disable open realm creation (`SETTING_OPEN_REALM_CREATION = "False"`) and use the ECS exec method to generate invitation-only creation links.

### Zulip Organization Creation Fails with Internal Server Error
**Problem**: Visiting `/new/` loads the form, but submitting it returns "Internal server error".

**Cause**: Zulip requires email to be properly configured to send confirmation emails during organization creation. If the SMTP username or password is missing/incorrect, organization creation silently fails with a 500 error.

**Solution**: Ensure the Zulip module passes both email credentials as secrets:
```hcl
secrets = {
  SECRETS_email_host_user     = "${module.ses_user.smtp_credentials_secret_arn}:username::"
  SECRETS_email_host_password = "${module.ses_user.smtp_credentials_secret_arn}:password::"
}
```

Also ensure the SES SMTP credentials secret is in the IAM policy for secrets access.

**Note**: The SES SMTP username is the access key ID (not the IAM user name). The password is derived from the secret access key using AWS's SES-specific algorithm. Both are stored in the `ses-smtp-user` module's Secrets Manager secret.

### Python Boolean Case Sensitivity
**Problem**: Zulip crashes with `NameError: name 'true' is not defined`.

**Cause**: Python booleans are `True`/`False` (capitalized), not `true`/`false`.

**Solution**: Use capitalized Python booleans in environment variables:
```hcl
SETTING_EMAIL_USE_TLS = "True"  # NOT "true"
```

### AUTHENTICATION_BACKENDS Must Be a Tuple
**Problem**: Zulip crashes with `TypeError: can only concatenate str (not "tuple") to str`.

**Cause**: `AUTHENTICATION_BACKENDS` expects a Python tuple, but passing a plain string breaks the internal concatenation logic in `computed_settings.py`.

**Solution**: Format the setting as a Python tuple:
```hcl
SETTING_AUTHENTICATION_BACKENDS = '("zproject.backends.GenericOpenIdConnectBackend",)'
```
Note the parentheses, quotes, and trailing comma.

### SSL Certificate Behind Load Balancer
**Problem**: Zulip fails with "SSL private key zulip.key is not present in /data".

**Cause**: Zulip doesn't know it's behind an ALB that terminates TLS.

**Solution**: Configure Zulip to recognize the load balancer:
```hcl
DISABLE_HTTPS               = "True"
SSL_CERTIFICATE_GENERATION  = "self-signed"
LOADBALANCER_IPS            = "10.0.0.0/16"  # VPC CIDR
```

### Database SSL Connection
**Problem**: Zulip fails with "Could not connect to database server. Exiting." when connecting to RDS PostgreSQL.

**Cause**: AWS RDS PostgreSQL requires SSL connections by default. Zulip's database configuration needs SSL mode configured.

**Solution**: Add SSL configuration for the database connection:
```hcl
SETTING_REMOTE_POSTGRES_SSLMODE = "require"
```

**Note**: Zitadel explicitly sets SSL mode with `ZITADEL_DATABASE_POSTGRES_USER_SSL_MODE = "require"`

### docker-zulip pg_isready Uses Different Environment Variables
**Problem**: Zulip container times out waiting for PostgreSQL with "Waiting for Postgres server... timeout" even when the RDS database is running and accessible.

**Cause**: The docker-zulip entrypoint script uses `pg_isready` to check database connectivity. The `pg_isready` command reads `DB_HOST`, `DB_HOST_PORT`, and `DB_USER` environment variables (defaulting to `127.0.0.1:5432`), **not** the `SETTING_*` prefixed variables that configure Zulip's Django settings.

**Solution**: Set both sets of environment variables:
```hcl
# For pg_isready in entrypoint script
DB_HOST      = "your-rds-endpoint.region.rds.amazonaws.com"
DB_HOST_PORT = "5432"
DB_USER      = "zulip"
PGSSLMODE    = "require"

# For Zulip's Django ORM
SETTING_DATABASES__default__NAME = "zulip"
SETTING_REMOTE_POSTGRES_SSLMODE  = "require"
```

### RDS PostgreSQL Cannot Use Custom Text Search Dictionaries
**Problem**: Zulip fails with error: `could not open dictionary file "/rdsdbbin/postgres-16.x.x/share/tsearch_data/en_us.dict": No such file or directory`

**Cause**: Zulip requires custom text search dictionaries (hunspell files) for full-text search. AWS RDS is a managed service that doesn't allow access to the PostgreSQL installation filesystem to add custom dictionary files.

**Solution**: Use PostgreSQL as an ECS sidecar container instead of RDS. The sidecar runs in the same task as Zulip:
- Use `zulip/zulip-postgresql:14` image (includes hunspell dictionaries)
- PostgreSQL sidecar exposes port 5432 on localhost (127.0.0.1)
- Zulip connects to `DB_HOST=127.0.0.1` with `PGSSLMODE=disable`
- Increases ECS task resource requirements (2048 CPU, 4096 MB memory)
- For dev: ephemeral storage is acceptable (data lost on task restart)
- For prod: use EFS with proper UID/GID configuration

### Zulip PostgreSQL Sidecar Requires zulip-postgresql Image
**Problem**: Standard `postgres:14-alpine` fails with `could not open dictionary file "/usr/local/share/postgresql/tsearch_data/en_us.dict": No such file or directory`

**Cause**: The standard PostgreSQL images don't include the hunspell dictionary files that Zulip requires for full-text search.

**Solution**: Use the `zulip/zulip-postgresql:14` image which includes the required dictionaries pre-installed.

### EFS Access Points Prevent chown Operations
**Problem**: PostgreSQL sidecar fails with `chown: /var/lib/postgresql/data/pgdata: Operation not permitted`

**Cause**: EFS access points enforce POSIX user identity and don't allow ownership changes, even when running as root. PostgreSQL's entrypoint script tries to chown the PGDATA directory during initialization.

**Solutions**:
1. Run the container as the postgres user directly (`user: "999:999"`) to skip the chown step
2. Use ephemeral storage for dev environments (simpler, but data lost on restart)
3. Ensure EFS access point UID/GID (999:999 for postgres) matches the container user

## ECS / Fargate

### Apple Silicon Macs Pull ARM64 Images by Default (Wrong for Fargate)
**Problem**: After syncing Docker images to ECR from an Apple Silicon Mac (M1/M2/M3), ECS Fargate tasks fail with:
```
exec /usr/local/bin/docker-entrypoint.sh: exec format error
```

**Cause**: Docker on Apple Silicon pulls ARM64 (linux/arm64) images by default. ECS Fargate runs on x86_64 (linux/amd64). When you `docker pull` → `docker tag` → `docker push` on a Mac, you're pushing ARM64 images to ECR, which Fargate can't execute.

**Critical**: Simply adding `--platform linux/amd64` to `docker pull` isn't enough if Docker already has the ARM64 image cached. Docker sees "I already have outlinewiki/outline:latest" and skips the pull, keeping the ARM64 variant.

**Solution**: Remove the cached image before pulling:
```bash
# Remove the cached (wrong architecture) image
docker rmi outlinewiki/outline:latest

# Pull with explicit platform
docker pull --platform linux/amd64 outlinewiki/outline:latest

# Verify architecture
docker inspect outlinewiki/outline:latest --format '{{.Architecture}}'
# Should output: amd64

# Now tag and push to ECR
docker tag outlinewiki/outline:latest $ECR_REGISTRY/outline:latest
docker push $ECR_REGISTRY/outline:latest
```

**The sync script** (`scripts/sync-images-to-ecr.sh`) includes `--platform linux/amd64`, but on first run you may need to clear local images.

**Affected images**: Any multi-arch image where Docker Hub provides both ARM64 and AMD64 variants. Single-arch images (AMD64 only) are not affected since there's no ARM64 variant to accidentally cache.

**Date**: 2026-02-01

### Docker Hub Rate Limits Cause Task Failures
**Problem**: ECS tasks fail to start with error: `CannotPullContainerError: pull image manifest has been retried 7 time(s): 429 Too Many Requests - Server message: toomanyrequests: You have reached your unauthenticated pull rate limit`

**Cause**: Docker Hub limits unauthenticated pulls to 100 per 6 hours per IP. ECS Fargate tasks pulling from Docker Hub share NAT gateway IPs, quickly exhausting the limit during deployments or restarts.

**Solutions** (in order of preference):
1. **Use ECR (recommended)**: Mirror images to your own ECR repositories
   ```bash
   # One-time setup
   aws ecr create-repository --repository-name zulip/docker-zulip
   docker pull zulip/docker-zulip:latest
   docker tag zulip/docker-zulip:latest $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/zulip/docker-zulip:latest
   docker push $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/zulip/docker-zulip:latest
   ```

2. **Authenticate to Docker Hub**: Create a Docker Hub account and store credentials in Secrets Manager, then configure ECS to use them via `repositoryCredentials`

3. **Use alternative registries**: GHCR (GitHub Container Registry) and Quay.io have higher rate limits

**Affected images in this project**:
- `zulip/docker-zulip` - Docker Hub
- `zulip/zulip-postgresql` - Docker Hub
- `linuxserver/bookstack` - Docker Hub
- `mattermost/mattermost-team-edition` - Docker Hub
- `ghcr.io/zitadel/zitadel` - GHCR (not affected)

### Duplicate Security Group Rules Cause Terraform Conflicts
**Problem**: Terraform fails with "A]aws_security_group_rule... already exists" when multiple app modules create the same ingress rules.

**Cause**: If multiple ECS services (e.g., Zulip, BookStack, Docusaurus) all use port 80 and each creates its own ALB→ECS security group rule, Terraform detects duplicate rules and fails.

**Solution**: Centralize security group rules in the ECS cluster module instead of individual app modules:
```hcl
# In ecs-cluster module
variable "alb_security_group_id" {
  type    = string
  default = null
}

variable "alb_ingress_ports" {
  type    = list(number)
  default = [80, 8080]
}

resource "aws_security_group_rule" "alb_to_ecs" {
  for_each                 = var.alb_security_group_id != null ? toset([for p in var.alb_ingress_ports : tostring(p)]) : toset([])
  type                     = "ingress"
  from_port                = tonumber(each.value)
  to_port                  = tonumber(each.value)
  protocol                 = "tcp"
  source_security_group_id = var.alb_security_group_id
  security_group_id        = aws_security_group.ecs_tasks.id
}
```

### Security Group Rules Exist in AWS But Not in State
**Problem**: Terraform fails with `InvalidPermission.Duplicate: the specified rule ... already exists` even though terraform plan shows it needs to create the rule.

**Cause**: The security group rule exists in AWS (from a previous partial apply, interrupted destroy, or manual creation) but isn't in terraform state. Terraform tries to create it, AWS rejects it as duplicate.

**Solution**: Import the existing rules into state:
```bash
terraform import 'module.ecs.aws_security_group_rule.alb_to_ecs["80"]' \
  'sg-XXXXXX_ingress_tcp_80_80_sg-YYYYYY'
```

**Import ID format for aws_security_group_rule**:
```
<security_group_id>_<type>_<protocol>_<from_port>_<to_port>_<source>
```

Where:
- `security_group_id`: The SG the rule is attached to (from error message)
- `type`: `ingress` or `egress`
- `protocol`: `tcp`, `udp`, `-1` (all), etc.
- `from_port` / `to_port`: Port numbers
- `source`: Source SG ID, CIDR, or `self`

**Example** (from error "peer: sg-0520a89f1ff46f8a7, TCP, from port: 8080"):
```bash
terraform import 'module.ecs.aws_security_group_rule.alb_to_ecs["8080"]' \
  'sg-06702356b21efdbd1_ingress_tcp_8080_8080_sg-0520a89f1ff46f8a7'
```

### EFS Requires Platform Version 1.4.0+
When using EFS volumes with Fargate, you must specify platform version 1.4.0 or higher:
```hcl
platform_version = "1.4.0"  # Required for EFS
```

### EFS Mount Timing
EFS mount targets take time to become DNS-resolvable. Tasks may fail initially with DNS resolution errors. ECS will retry and eventually succeed once mount targets are ready.

### Secrets Manager JSON Format
When referencing individual keys from a JSON secret in ECS task definitions, use the format:
```
${secret_arn}:key_name::
```
Note the trailing `::` (empty version stage and version ID).

## BookStack

### OIDC Dependency on Zitadel
BookStack SSO won't work until:
1. Zitadel is fully running and accessible
2. An OIDC client is created in Zitadel
3. Client ID/Secret are configured in BookStack

## General Tips

### Local Testing First
Before deploying to ECS, test configurations locally with Docker Compose to catch configuration errors faster. See the `local/` directory for the development environment.

### Health Check Paths
- Zitadel: `/debug/healthz`
- Zulip: `/login/` (use matcher `200-399,400` - see ALB health check gotcha below)
- BookStack: `/status`
- Mattermost: `/api/v4/system/ping`
- Docusaurus: `/` (static site)

### ALB + Zitadel Terraform Provider Requires HTTP/2 Protocol
**Problem**: Zitadel Terraform provider fails with `unexpected HTTP status code received from server: 464 (); malformed header: missing HTTP content-type`.

**Cause**: The Zitadel Terraform provider uses gRPC to communicate with Zitadel's API. AWS ALB defaults to HTTP/1.1 for target groups, which doesn't properly handle gRPC traffic. The 464 error is the ALB failing to forward gRPC requests correctly.

**Solution**: Configure the ALB target group with `protocol_version = "HTTP2"`:
```hcl
# In ecs-service module
resource "aws_lb_target_group" "main" {
  protocol_version = var.target_group_protocol_version  # Set to "HTTP2" for Zitadel
  # ... other config
}

# In zitadel app module
module "service" {
  target_group_protocol_version = "HTTP2"  # Required for gRPC/Terraform provider
}
```

**Note**: Changing `protocol_version` forces target group replacement. You may need to delete the old target group and listener rule manually before Terraform can create the new one.

**Reference**: [GitHub Issue #208](https://github.com/zitadel/terraform-provider-zitadel/issues/208)

### Consider Kubernetes for Zitadel
**Context**: Most Zitadel documentation, examples, and community support assume Kubernetes with nginx or Traefik as the ingress controller. The Terraform provider and tooling are tested against these setups.

**AWS ECS Fargate works** but requires workarounds like the HTTP/2 protocol version fix above. If Zitadel becomes a maintenance burden, consider:
1. **Zitadel Cloud** (~$100/mo) - eliminates self-hosting complexity
2. **Small EKS cluster** - better alignment with Zitadel's expected environment
3. **EC2 + nginx** - simpler than ECS, follows standard Zitadel docs

For other services (BookStack, Zulip, Mattermost, Docusaurus), ECS Fargate remains a good choice.

### ALB Health Check Returns 400 Without Host Header
**Problem**: ALB target group shows "unhealthy" with "Health checks failed with these codes: [400]"

**Cause**: ALB health checks don't include a Host header by default. Services configured with virtual hosts (like nginx) return 400 "Bad Request" when they can't match the hostname.

**Solution**: Configure the target group matcher to accept 400 as a healthy response:
```hcl
health_check_path    = "/"
health_check_matcher = "200-399,400"
```
This works because:
1. A 400 response proves the container is running and nginx is responding
2. Real traffic through the ALB includes the Host header from the URL
3. The service works correctly for actual users

### ECS Services Cannot Reach Public URLs That Route Back to the Same ALB (Hairpin NAT)
**Problem**: OIDC discovery fails from ECS containers with errors like:
- BookStack: "OIDC Discovery Error: Error discovering provider settings from issuer at URL https://auth.dev.almondbread.org/.well-known/openid-configuration"
- Zulip: "The OpenID Connect backend is not configured correctly"

The OIDC endpoint works from the public internet (curl returns 200), but fails from inside the VPC.

**Cause**: This is a "hairpin NAT" or "NAT loopback" issue:
1. ECS tasks resolve `auth.dev.almondbread.org` to the ALB's public IP
2. Traffic goes out through NAT gateway to the internet
3. Traffic needs to come back in through the ALB
4. The return path breaks because the source IP gets translated

**What DOESN'T work**:
- **Route53 Private Hosted Zone with internet-facing ALB**: Even with a private zone pointing to the ALB's DNS name, an internet-facing ALB only has public IPs. The private zone resolves to the same public IPs, so the hairpin NAT issue persists. This approach only works if the ALB is internal or dual-stack.

**Solutions** (in order of preference):
1. **Internal ALB for service-to-service communication** (recommended): Create a separate internal ALB that apps use for OIDC discovery and inter-service calls. The internal ALB has private IPs that are directly routable within the VPC.
   ```hcl
   # Internal ALB for service-to-service communication
   resource "aws_lb" "internal" {
     name               = "${var.project}-${var.environment}-internal"
     internal           = true  # Key difference: internal = true
     load_balancer_type = "application"
     security_groups    = [aws_security_group.internal_alb.id]
     subnets            = var.private_subnet_ids
   }

   # Apps use internal ALB URL for OIDC issuer
   # e.g., https://auth-internal.dev.almondbread.org
   ```

   Configure apps to use the internal ALB endpoint for OIDC discovery while users access the public ALB.

2. **Service Discovery with Cloud Map**: Use AWS Cloud Map for internal service discovery. Configure apps to use internal DNS names like `zitadel.cochlearis.internal` for server-to-server communication.

3. **VPC Endpoints / PrivateLink**: More complex but provides private connectivity to the ALB without NAT gateway involvement.

**Note**: This issue affects any scenario where ECS services need to call each other through a public load balancer. For ECS-to-ECS communication, always prefer internal networking.

### Internal ALB Implementation Details
**Context**: When implementing an internal ALB for service-to-service communication (to solve hairpin NAT), there are several AWS/Terraform constraints to be aware of.

**Target Groups Cannot Be Shared Across ALBs**:
AWS doesn't allow a single target group to be associated with multiple load balancers. Error: `TargetGroupAssociationLimit: The following target groups cannot be associated with more than one load balancer`.

**Solution**: Create separate target groups for each ALB:
```hcl
# Original target group (created by ecs-service module for public ALB)
# cochlearis-dev-zitadel

# Separate target group for internal ALB
resource "aws_lb_target_group" "zitadel_internal" {
  name             = "${var.project}-${var.environment}-zitadel-int"
  port             = 8080
  protocol         = "HTTP"
  protocol_version = "HTTP2"  # Match the original
  vpc_id           = module.vpc.vpc_id
  target_type      = "ip"
  # ... health check config matching original
}
```

**ECS Services Must Register with Both Target Groups**:
ECS services can register with multiple target groups via multiple `load_balancer` blocks. The ecs-service module needs an `additional_target_group_arns` variable:
```hcl
# In ecs-service module
dynamic "load_balancer" {
  for_each = var.additional_target_group_arns
  content {
    target_group_arn = load_balancer.value
    container_name   = var.service_name
    container_port   = var.container_port
  }
}
```

**Security Group Rules Need Both ALBs**:
Don't forget to add ingress rules from the internal ALB to ECS tasks. Without these, health checks will fail:
```hcl
# Internal ALB needs to reach ECS tasks on the service port
variable "internal_alb_security_group_id" { ... }
variable "internal_alb_ingress_ports" { ... }

resource "aws_security_group_rule" "internal_alb_to_ecs" {
  for_each = toset([for p in var.internal_alb_ingress_ports : tostring(p)])
  type                     = "ingress"
  from_port                = tonumber(each.value)
  to_port                  = tonumber(each.value)
  protocol                 = "tcp"
  source_security_group_id = var.internal_alb_security_group_id
  security_group_id        = aws_security_group.ecs_tasks.id
}
```

### ECS Tasks Cache DNS Resolution at Startup
**Problem**: After fixing DNS records (e.g., pointing a private zone record to an internal ALB), running ECS tasks still fail because they cached the old DNS resolution.

**Cause**: ECS Fargate tasks resolve DNS at container startup and may cache results. Containers started before a DNS change will continue using the old resolution until restarted.

**Symptoms**:
- Test tasks (newly launched) work correctly
- Running service tasks fail with the same request
- Logs show connection failures to IP addresses that are no longer valid

**Solution**: Force a new deployment after DNS changes:
```bash
aws ecs update-service --cluster CLUSTER --service SERVICE --force-new-deployment
```

**Verification**: Before assuming a fix works, always test from a freshly-launched task:
```bash
# Run a one-off task to test connectivity
aws ecs run-task \
  --cluster CLUSTER \
  --task-definition TASK_DEF \
  --overrides '{"containerOverrides":[{"name":"CONTAINER","command":["sh","-c","nslookup HOSTNAME && curl ENDPOINT"]}]}' \
  --network-configuration "awsvpcConfiguration={...}"
```

**Note**: ECS Exec (`aws ecs execute-command`) may not work with all container images (requires SSM agent). The run-task approach with command override is more reliable for debugging.

### Terraform Targeted Apply Can Leave State Incomplete
**Problem**: Using `terraform apply -target=...` to apply specific resources can leave other resources missing from state or partially configured.

**Common Issues**:
1. Security group rules not created when targeting only the service
2. Target group registrations missing when service isn't redeployed
3. Dependent resources left in pending state
4. **DNS records not updated** - critical for internal ALB routing fixes

**Solution**: After targeted applies, always run a full `terraform plan` to verify state completeness. Consider using AWS CLI for emergency fixes while waiting for full terraform runs:
```bash
# Emergency security group rule addition
aws ec2 authorize-security-group-ingress \
  --group-id sg-ecs-tasks \
  --protocol tcp --port 8080 \
  --source-group sg-alb
```

### Terraform State Locks Can Become Stale
**Problem**: If a terraform command is interrupted (Ctrl+C, timeout, crash), the state lock may remain in DynamoDB, blocking subsequent commands.

**Error**: `Error: Error acquiring the state lock`

**Solution**:
```bash
# Note the Lock ID from the error message, then:
terraform force-unlock -force <lock-id>

# Example:
terraform force-unlock -force 6ab2905a-4009-6ad1-536e-f3a3ebb19609
```

**Caution**: Only force-unlock if you're certain no other terraform operation is running. Check AWS CloudWatch or console for active terraform processes first.

### Zitadel OIDC Module Requires Separate Terraform Root
**Problem**: When deploying from scratch (after a `terraform destroy` or on a new environment), `terraform apply` fails with:
```
Error: failed to start zitadel client: OpenID Provider Configuration Discovery has failed
Get "https://auth.dev.almondbread.org/.well-known/openid-configuration": dial tcp X.X.X.X:443: i/o timeout
```
or:
```
Error: failed to start zitadel client: PEM decode failed
```

**Cause**: The Zitadel Terraform provider initializes and tries to connect to Zitadel during `terraform init`/`terraform plan`, before any resources are created. On a fresh deploy, Zitadel doesn't exist yet. Simply setting `enable_zitadel_oidc = false` is NOT enough - the provider still initializes and fails.

**Solution**: Use a separate Terraform root for OIDC configuration:

```
environments/aws/dev/
├── main.tf              # Core infra (no zitadel provider)
├── terraform.tf         # Only aws and random providers
└── oidc/                # Separate Terraform root
    ├── main.tf          # Creates OIDC clients, writes to SSM
    ├── terraform.tf     # Has zitadel provider
    └── providers.tf     # Zitadel provider configuration
```

The main `dev/` root reads OIDC configuration from SSM Parameter Store (written by `dev/oidc/`).

**Deploy order**:
1. `terraform apply` in `dev/` - creates all infrastructure including Zitadel
2. Wait for Zitadel to become healthy
3. `terraform apply` in `dev/oidc/` - creates OIDC clients, writes config to SSM
4. Set `enable_zitadel_oidc = true` in `dev/terraform.tfvars`
5. `terraform apply` in `dev/` - apps pick up OIDC config from SSM

**Why a separate root instead of commenting/uncommenting code**: Commenting out provider blocks is error-prone, not automatable, and terrible developer experience. A separate Terraform root cleanly separates concerns and works reliably.

**Why simply setting the variable to false doesn't work**: Terraform initializes ALL providers declared in `required_providers`, regardless of whether any resources use them. Even with `count = 0` on the module, the provider block is evaluated and tries to connect.

**Note**: This only affects fresh deployments. Once Zitadel is running and `dev/oidc/` has been applied, subsequent applies in `dev/` work normally because the SSM parameters exist.

### Removing a Provider Requires Clearing Terraform Cache
**Problem**: After removing a provider from `required_providers`, terraform still tries to configure it and fails with errors like:
```
Error: Missing required argument
The argument "domain" is required, but was not set.
```

**Cause**: Terraform caches provider binaries and lock files in `.terraform/` and `.terraform.lock.hcl`. Even after removing a provider from your configuration, the cached state still references it.

**Solution**: Clear the cache and reinitialize:
```bash
rm -rf .terraform
rm -f .terraform.lock.hcl
terraform init
```

**When this happens**:
- Removing a provider from `required_providers`
- Moving a module that uses a provider to a different Terraform root
- Switching from one provider version to another with breaking changes

**Note**: `terraform init -upgrade` is often not enough - it upgrades providers but doesn't remove cached ones that are no longer in the configuration. A full cache clear is more reliable.

### Remote State Can Have Resources Requiring Removed Providers
**Problem**: Even after clearing `.terraform/` and `.terraform.lock.hcl`, terraform still fails with provider configuration errors like:
```
Error: Missing required argument
The argument "domain" is required, but was not set.
```

**Cause**: The **remote state** (in S3, not local cache) still contains resources that were managed by the removed provider. Terraform needs to configure the provider to manage those resources, even if you've removed it from your configuration. This commonly happens when:
- A `terraform destroy` was interrupted or didn't fully complete
- You removed a module from configuration without destroying its resources first
- You moved resources to a different Terraform root

**Diagnosis**: Check for orphaned resources in state:
```bash
terraform state list | grep <provider-related-pattern>
# Example: terraform state list | grep zitadel
```

**Solution**: Remove the orphaned resources from state:
```bash
terraform state rm '<resource_address>'
# Example:
terraform state rm 'module.zitadel_oidc[0].zitadel_project.main'
terraform state rm 'module.zitadel_oidc[0].zitadel_application_oidc.bookstack'
```

**Caution**: This only removes from state - it doesn't destroy the actual resources. If the resources still exist in the cloud provider, they become "orphaned" and must be cleaned up manually or imported into another Terraform configuration.

**Prevention**: For the zitadel_oidc case specifically, run `pre-apply.sh` before terraform apply:
```bash
./pre-apply.sh && terraform apply
```

This script automatically detects and removes orphaned zitadel resources from state.

**Best Practice**: When removing a module that uses a unique provider:
1. First destroy the resources: `terraform destroy -target=module.xxx`
2. Then remove the module from configuration
3. Then remove the provider from `required_providers`

### Database Password Special Characters Break Connection URLs
**Problem**: Mattermost crashes with "net/url: invalid userinfo" when connecting to RDS PostgreSQL.

**Cause**: Random passwords containing characters like `[`, `]`, `&`, `:`, `(`, `)` break database connection URL parsing. These characters have special meaning in URLs and aren't properly escaped.

**Solution**: Generate passwords without special characters:
```hcl
resource "random_password" "master" {
  length  = 32
  special = false  # Avoid URL-breaking special characters
}
```

**Note**: This reduces password entropy slightly, but a 32-character alphanumeric password is still secure. Alternatively, ensure all services use escaped/quoted passwords rather than URL-style connection strings.

### AWS Secrets Manager Force-Delete Has Propagation Delay
**Problem**: After running `aws secretsmanager delete-secret --force-delete-without-recovery`, Terraform still fails with "secret with this name is already scheduled for deletion" when trying to recreate secrets.

**Cause**: AWS Secrets Manager has eventual consistency. Even with `--force-delete-without-recovery`, the deletion takes 30-120 seconds to propagate across AWS infrastructure. The API returns success immediately, but the secret name remains reserved until full propagation completes.

**Solutions**:
1. **Use unique names (recommended)**: Add random suffixes to secret names to avoid collision permanently:
   ```hcl
   resource "random_id" "secret_suffix" {
     byte_length = 4
   }

   resource "aws_secretsmanager_secret" "master_password" {
     name = "${local.name_prefix}-master-password-${random_id.secret_suffix.hex}"
   }
   ```
2. **Wait and retry**: Wait 2-3 minutes after force-deleting secrets before running `terraform apply`
3. **Import existing secrets**: If the secret still exists, import it into Terraform state instead of recreating

**Workaround script**:
```bash
# Force delete all secrets matching a pattern
for secret in $(aws secretsmanager list-secrets --include-planned-deletion \
    --query 'SecretList[?contains(Name, `myprefix`)].Name' --output text); do
  aws secretsmanager delete-secret --secret-id "$secret" --force-delete-without-recovery
done

# Wait for propagation
sleep 120

# Then run terraform apply
terraform apply
```

**Note**: This is a known AWS limitation, not a Terraform bug. The `list-secrets` command may return empty even while deletion is still propagating internally.

**Important**: When using random suffixes, ensure ALL modules that create Secrets Manager secrets use this pattern. Inconsistent application will cause failures when some secrets exist and others don't. Modules that need this pattern:
- `modules/aws/rds-postgres/main.tf`
- `modules/aws/rds-mysql/main.tf`
- `modules/aws/ses-smtp-user/main.tf`
- `modules/aws/apps/bookstack/main.tf`
- `modules/aws/apps/mattermost/main.tf`
- `modules/aws/apps/zitadel/main.tf`
- `modules/aws/apps/zulip/main.tf`
- `modules/aws/zitadel-oidc/main.tf`

## Application-Specific OIDC Issues

### BookStack (Laravel) Behind ALB Needs APP_PROXIES for HTTPS
**Problem**: BookStack OIDC login silently fails. The `/oidc/login` endpoint returns a 302 redirect to `/login` instead of redirecting to the IdP. No errors appear in logs.

**Cause**: Laravel apps behind SSL-terminating load balancers don't know the original request was HTTPS. Without trusting proxy headers, Laravel generates `http://` callback URLs. Zitadel (or any OIDC provider) rejects these because the redirect URI doesn't match the registered `https://` callback.

**Why it's silent**: Laravel doesn't log this as an error because from its perspective, it correctly generated the callback URL - it just doesn't know it should be HTTPS.

**Solution**: Set `APP_PROXIES="*"` to trust the `X-Forwarded-Proto` header from the ALB:
```hcl
environment_variables = {
  APP_URL     = "https://docs.example.com"
  APP_PROXIES = "*"  # Trust ALB's X-Forwarded-Proto header
  # ... other variables
}
```

**Verification**: After fix, the OIDC login should redirect to the IdP's authorize endpoint with a proper `redirect_uri=https://...` parameter.

**Applies to**: Any Laravel application behind a load balancer (BookStack, Outline if using Laravel, etc.)

### Mattermost Team Edition Requires `read_user` Scope for GitLab OAuth
**Problem**: Mattermost Team Edition doesn't show the GitLab/SSO login button on the login page, even though `MM_GITLABSETTINGS_ENABLE=true` and all other OAuth settings are configured.

**Cause**: Mattermost Team Edition uses a GitLab-compatible OAuth adapter, NOT standard OIDC. The GitLab adapter strictly requires the `read_user` scope. If you provide standard OIDC scopes like `openid profile email`, the adapter doesn't recognize them and silently disables the SSO button.

**Wrong configuration**:
```hcl
MM_GITLABSETTINGS_SCOPE = "openid profile email"  # WRONG for Team Edition
```

**Correct configuration**:
```hcl
MM_GITLABSETTINGS_SCOPE = "read_user"  # Required for GitLab OAuth adapter
```

**Note**: Mattermost Enterprise Edition has native OIDC support with standard scopes. Team Edition only supports GitLab-style OAuth, which requires adapting your IdP to provide a GitLab-compatible response.

**Zitadel compatibility**: Zitadel's OAuth2 endpoints work with the GitLab adapter when using `read_user` scope and configuring the userinfo endpoint correctly.

### Existing Zitadel Resources Block Terraform Apply
**Problem**: Running `terraform apply` in `dev/oidc/` fails with:
```
Error: failed to create project: rpc error: code = AlreadyExists desc = Project already exists on organization
```

**Cause**: The Zitadel database survived `terraform destroy` (see "RDS Database Data Can Survive Terraform Destroy" below), so resources like projects, OIDC applications, and service accounts still exist. Terraform tries to create them fresh and Zitadel rejects the duplicate.

**Solution**: Import existing resources into Terraform state.

**Option 1: Use helper script (recommended)**
```bash
cd environments/aws/dev
ZITADEL_PAT="<your-pat>" ./list-zitadel-resources.sh
```
This outputs ready-to-use import commands. Copy/paste them into `dev/oidc/`.

**Option 2: Manual lookup**
```bash
# Find the project ID in Zitadel UI: Projects → click project → ID is in the URL
terraform import 'module.zitadel_oidc.zitadel_project.main' '<project-id>'

# For OIDC applications: format is <app_id>:<project_id>
terraform import 'module.zitadel_oidc.zitadel_application_oidc.bookstack' '<app-id>:<project-id>'
```

**Import ID formats for Zitadel resources**:
- `zitadel_project`: Just the project ID (e.g., `358114162284432499`)
- `zitadel_application_oidc`: `<app_id>:<project_id>` (e.g., `358114162368318579:358114162284432499`)

**Alternative**: Delete the existing resources in Zitadel UI and let Terraform create fresh ones. This is cleaner but loses any manual configuration.

### RDS Database Data Can Survive Terraform Destroy
**Problem**: After running `terraform destroy` and `terraform apply` to get a "fresh" environment, old application data persists. For example, Zitadel still has old service accounts, user accounts, or configuration from before the destroy.

**Cause**: RDS database data can survive destruction in several ways:
1. **Final snapshot restoration**: If `skip_final_snapshot = false` (the default), AWS creates a final snapshot before deletion. On reapply, Terraform may restore from this snapshot.
2. **Destruction interrupted**: If `terraform destroy` is interrupted (Ctrl+C, timeout, error), RDS may not be deleted.
3. **Deletion protection**: If `deletion_protection = true` was set, RDS won't be deleted (you'd see an error, but may not notice it among other output).
4. **Snapshot retention**: Even with `skip_final_snapshot = true`, automated backups may exist.

**How to verify**: Check the RDS creation timestamp:
```bash
aws-vault exec cochlearis --no-session -- aws rds describe-db-instances \
  --region eu-central-1 \
  --query 'DBInstances[*].{ID:DBInstanceIdentifier,Created:InstanceCreateTime}' \
  --output table
```
If the creation time is older than your last destroy, the database survived.

**For truly fresh Zitadel**: Per GUIDERAILS.md, Zitadel `FIRSTINSTANCE_*` variables only work on first database init. If old data persists, you have a "Frankenstein" state. Options:
1. **Proceed anyway** - might work, might have subtle issues
2. **Manually delete data** - drop the Zitadel schema or specific tables
3. **Delete RDS manually** - `aws rds delete-db-instance --db-instance-identifier ID --skip-final-snapshot --delete-automated-backups`, then reapply

**Prevention**: For dev environments where fresh state matters, explicitly configure:
```hcl
skip_final_snapshot       = true
delete_automated_backups  = true
deletion_protection       = false
```

**Lesson learned**: Don't assume `terraform destroy` gives you a clean slate. Always verify with timestamps or by checking application state.

### OIDC Auth Method: BASIC vs POST
**Problem**: OIDC authentication fails even when network connectivity and redirect URIs are correct.

**Cause**: Different applications expect the client secret to be sent differently:
- **BASIC**: Client ID and secret sent in the `Authorization: Basic` header (base64-encoded)
- **POST**: Client ID and secret sent in the request body

**In Zitadel Terraform**:
```hcl
resource "zitadel_application_oidc" "app" {
  # Try BASIC first (more common)
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_BASIC"

  # If BASIC fails, try POST
  # auth_method_type = "OIDC_AUTH_METHOD_TYPE_POST"
}
```

**Known preferences**:
- BookStack: Works with BASIC
- Mattermost (GitLab adapter): Works with BASIC
- Outline: Works with BASIC
- Some older apps: May require POST

**Debugging tip**: If OIDC fails at the token exchange step (after IdP redirect), try switching the auth method.

---

## Zitadel OIDC: Abandoned After 48 Hours

**Date**: 2026-02-01

**Status**: ABANDONED - Switched to Google OAuth for production use

### What We Tried

Over a 48-hour period (entire weekend), we attempted to get Zitadel OIDC working for BookStack, Mattermost, Zulip, and Outline. The following were attempted:

1. **Network Layer**: Diagnosed and solved hairpin NAT issue with internal ALB + private DNS zone
2. **Infrastructure**: Created separate Terraform root (`dev/oidc/`) to solve provider chicken-and-egg
3. **Bootstrap Scripts**: Created `bootstrap-zitadel-oidc.sh` and `list-zitadel-resources.sh`
4. **App Configuration**: Added `APP_PROXIES="*"` for BookStack, `read_user` scope for Mattermost
5. **Terraform Imports**: Imported existing Zitadel resources after RDS survival
6. **Force Redeployments**: Multiple ECS service force-new-deployments
7. **DNS Verification**: Confirmed internal DNS resolution working
8. **SSL Certificates**: Verified internal ALB has valid cert for auth.dev.almondbread.org
9. **Target Health**: Confirmed Zitadel healthy on internal ALB

### The Final Error

Despite all infrastructure being correct:
- Internal ALB listener rule exists for `auth.dev.almondbread.org`
- Private DNS zone resolves to internal ALB
- SSL cert valid
- Zitadel target healthy

BookStack still showed:
```
OIDC Discovery Error: Error discovering provider settings from issuer at URL
https://auth.dev.almondbread.org/.well-known/openid-configuration
```

Even though curling that URL from outside returns valid OIDC discovery JSON.

### Why We Stopped

1. **Time constraint**: Needed functional services for collaborative event
2. **No progress signal**: Despite 48 hours, never saw a successful OIDC redirect
3. **Diminishing returns**: Each "fix" led to another layer of debugging
4. **Business priority**: Data fabric work takes precedence over IdP perfection

### What's Working Instead

**Google OAuth**: BookStack and Zulip now use Google OAuth directly. Simpler, proven, no self-hosted IdP complexity.

**Local Auth**: Username/password as fallback where Google isn't preferred.

### If Picking This Up Later

1. **Read `OIDC.md`** - Full history of attempts and configuration
2. **Start fresh**: Consider deleting Zitadel RDS and starting clean
3. **Try Zitadel v3**: v4's split Login UI may be part of the problem
4. **Consider alternatives**: Keycloak, Authentik, or cloud IdPs (Auth0, Okta)
5. **Test from inside VPC**: Don't trust external curls - test from an ECS task

### Lessons Learned

1. Self-hosted IdPs are high maintenance for small teams
2. "Works from my laptop" != "works from inside VPC"
3. LLM assistants don't understand hairpin NAT or ECS networking edge cases
4. Zitadel v4's architecture split adds significant complexity
5. Sometimes the pragmatic choice is using a proven cloud service

### Why This Is Hard (Gemini Analysis)

**You are not being gaslit**: Zitadel OIDC is a real, high-performance solution, but you are hitting the "Bleeding Edge" wall.

The transition from Zitadel v3 to v4 changed the fundamental way the OIDC flow is handled. It moved from a "monolithic" login handled by one binary to a decoupled system. When an LLM like Claude looks at documentation, it often blends v2, v3, and v4 instructions into a "hallucination cocktail" that ignores the breaking changes in the API and UI layers.

**People who succeed usually fall into two camps:**

1. **The "Old Guard"**: Running Zitadel **v3.x** because it's "boring" and just works. Everything is in one binary, and the OIDC flows are well-documented.

2. **The "K8s Native"**: Running v4 on **Kubernetes** using the official Helm chart, which handles the complex routing for the new Login V2 automatically.

**Why this specific architecture is hard:**

We are likely among the first people trying to deploy **Zitadel v4 in a Fargate Sidecar pattern with an Internal ALB for Hairpin NAT bypass**. This is a highly specific, high-complexity architecture.

The `code 5: Not Found` errors occur because v4 expects a separate frontend to handle the OIDC callback, and in our "simplified" ECS setup, that frontend literally doesn't exist.

**Verdict**: For Decision Velocity, use Azure AD and Google OAuth. Zitadel OIDC is a future-state goal, not a sprint-1 blocker.

---

## Zulip Sidecar Pattern Issues (HISTORICAL)

**Date**: 2026-02-01

**Status**: ABANDONED - See "Zulip Cannot Run Self-Contained in ECS Fargate" for resolution

### The Problem

Zulip deployed with:
- PostgreSQL sidecar container (`zulip/zulip-postgresql:14`)
- External ElastiCache Redis
- EFS for persistent storage

Results in "Internal server error" when creating organizations at `/new/`.

### Symptoms

**All Zulip event workers crash continuously:**
```
WARN exited: zulip_events_deferred_email_senders (exit status 1; not expected)
INFO spawned: 'zulip_events_deferred_email_senders' with pid 709
WARN exited: zulip_events_thumbnail (exit status 1; not expected)
... (pattern repeats for ALL event workers)
```

Workers affected:
- `zulip_events_deferred_email_senders`
- `zulip_events_thumbnail`
- `zulip_events_missedmessage_emails`
- `zulip_events_user_activity`
- `zulip_events_email_senders`
- And 8+ more...

### What We Tried

1. **Email credentials fix**: Added `SECRETS_email_host_user` and `SECRETS_email_host_password`
2. **Force redeployment**: Multiple ECS service redeploys
3. **Log analysis**: No Python tracebacks visible, only supervisor messages
4. **Redis verification**: ElastiCache shows available

### Potential Root Causes (From Gemini Analysis)

1. **EFS permission mismatch**: Zulip runs as user 1000, but EFS mounts may be root (0)
   - Workers crash trying to write logs/temp files

2. **Sidecar timing**: PostgreSQL sidecar may not be ready when Zulip workers start
   - Workers try to connect, fail, exit with status 1

3. **ALB X-Forwarded-Proto**: May need explicit header forwarding for HTTPS

4. **SES "From" address not verified** (Gemini suggestion):
   - Zulip's `EmailAuthBackend` is mandatory for first org creation
   - If SES credentials are correct but the "From" address isn't verified, Python crashes when sending the "Welcome" email during `/new/`
   - **Fix**: Verify the sender email address in SES Console as a "Verified Identity"

### Workaround: Zulip Mini

Created a simplified all-in-one deployment at `modules/aws/apps/zulip-mini/`:

- **No PostgreSQL sidecar**: Uses docker-zulip's internal PostgreSQL
- **No external Redis**: Uses docker-zulip's internal Redis
- **EFS with uid 1000**: Correct permissions for Zulip user
- **Simpler config**: Fewer moving parts to break

**URL**: `https://chatmini.dev.almondbread.org`

This runs alongside the original Zulip (`https://chat.dev.almondbread.org`) for comparison and troubleshooting.

### Resolution

Both the sidecar pattern and all-in-one (zulip-mini) approaches failed. The fundamental issue is that docker-zulip requires supervisord to manage multiple processes, which doesn't work in ECS Fargate's single-process container model.

**See**: "Zulip Cannot Run Self-Contained in ECS Fargate" section below for full analysis.

**Action taken**: Switched to EC2 VM deployment using standard Zulip installation.

### Files (REMOVED)

- `modules/aws/apps/zulip/` - Removed (ECS sidecar pattern)
- `modules/aws/apps/zulip-mini/` - Removed (ECS all-in-one pattern)

### Files (ADDED)

- `modules/aws/apps/zulip-ec2/` - EC2 VM with standard installation

---

## Outline Node.js Rejects RDS SSL Certificate

**Date**: 2026-02-01

**Problem**: Outline container fails to start with:
```
SequelizeConnectionError: self-signed certificate in certificate chain
```

**Cause**: Outline uses Node.js with Sequelize ORM to connect to PostgreSQL. Node.js has stricter SSL certificate validation than other database clients. AWS RDS PostgreSQL uses certificates signed by Amazon's CA, which Node.js doesn't trust by default. Even with `sslmode=require` in the DATABASE_URL, Node.js's TLS layer rejects the certificate before PostgreSQL's SSL handshake completes.

**Wrong solution (doesn't work)**:
```hcl
PGSSLMODE = "no-verify"  # INVALID - Outline validates this
```
Outline validates PGSSLMODE against standard PostgreSQL values (`disable`, `allow`, `require`, `prefer`, `verify-ca`, `verify-full`). The value `no-verify` is not standard PostgreSQL and causes Outline to fail with:
```
Environment configuration is invalid, please check the following:
- PGSSLMODE must be one of the following values: disable, allow, require, prefer, verify-ca, verify-full
```

**Correct solution**: Disable Node.js TLS certificate validation globally:
```hcl
environment_variables = {
  NODE_TLS_REJECT_UNAUTHORIZED = "0"  # Disable Node.js cert validation
  # ... other variables
}
```
This bypasses Node.js's TLS layer entirely, allowing Outline to connect to RDS without validating the certificate.

**Warning**: You'll see this in the logs (expected):
```
(node:20) Warning: Setting the NODE_TLS_REJECT_UNAUTHORIZED environment variable to '0' makes TLS connections and HTTPS requests insecure by disabling certificate verification.
```

**Why this is different from other apps**:
- **Zulip** (Python/Django): Uses `psycopg2` which respects `sslmode=require` without validating the CA
- **Mattermost** (Go): Uses Go's database/sql which has different certificate handling
- **Outline** (Node.js): Uses `pg` package which delegates to Node.js TLS, stricter by default

**Production alternative**: Instead of disabling TLS validation, download the RDS CA bundle and configure Sequelize to trust it:
```js
ssl: {
  ca: fs.readFileSync('/path/to/rds-ca-bundle.pem')
}
```

But for dev environments, `NODE_TLS_REJECT_UNAUTHORIZED=0` is simpler.

---

## Outline Requires an OAuth Provider (No Email-Only Login)

**Date**: 2026-02-02

**Status**: FUNDAMENTAL LIMITATION - Outline requires OAuth/SSO, not email login

### The Problem

Outline does **NOT** support standalone email/password or magic link authentication. It **requires** an OAuth provider (Google, Azure AD, Slack, or OIDC). SMTP configuration is only for sending notification emails, not for login.

If you configure only SMTP without an OAuth provider, the login page shows nothing — no buttons, no email form, nothing.

### Common Misconception

**WRONG**: "Configure SMTP and users can log in with email/magic link"
**CORRECT**: "SMTP is for notifications. You MUST configure an OAuth provider for login."

### Why Google/Azure OAuth Don't Work with Personal Accounts

Google and Azure AD OAuth require organizational accounts:
- **Google OAuth**: Requires Google Workspace accounts (not personal @gmail.com)
- **Azure AD OAuth**: Requires organizational accounts (not personal @outlook.com)

Outline uses the `hd` (hosted domain) field from Google OAuth, which personal accounts don't have.

### Solution: Slack OAuth

**Slack OAuth works with ANY Slack workspace** — including free/personal workspaces. No enterprise requirement.

**Setup steps:**

1. **Create Slack App** at https://api.slack.com/apps
   - Click "Create New App" → "From scratch"
   - Name it (e.g., "Outline") and select your workspace

2. **Configure OAuth & Permissions**:
   - Add redirect URL: `https://wiki.dev.almondbread.org/auth/slack.callback`
   - Add scopes: `identity.avatar`, `identity.basic`, `identity.email`, `identity.team`

3. **Get credentials**:
   - Copy "Client ID" and "Client Secret" from "Basic Information"

4. **Store secret in AWS Secrets Manager**:
   ```bash
   aws-vault exec cochlearis --no-session -- aws secretsmanager create-secret \
     --name cochlearis-dev-outline-slack-oauth \
     --secret-string '{"client_secret":"YOUR_SECRET"}' \
     --region eu-central-1
   ```

5. **Configure Terraform** (terraform.tfvars):
   ```hcl
   outline_slack_client_id  = "YOUR_CLIENT_ID"
   outline_slack_secret_arn = "arn:aws:secretsmanager:eu-central-1:ACCOUNT:secret:cochlearis-dev-outline-slack-oauth-SUFFIX"
   ```

6. **Apply and redeploy**:
   ```bash
   terraform apply
   aws ecs update-service --cluster cochlearis-dev-cluster --service outline --force-new-deployment --region eu-central-1
   ```

### Alternative Options

1. **Slack OAuth** (RECOMMENDED) - Works with any Slack workspace including free/personal
2. **Google Workspace accounts** - If you have organizational accounts
3. **Azure AD organizational accounts** - Same requirement
4. **OIDC via Zitadel** - On hold due to complexity (see "Zitadel OIDC: Abandoned After 48 Hours")
5. **SAML** - For enterprise SSO providers
6. **Use BookStack instead** - Supports username/password natively

### References

- [Outline Authentication Docs](https://docs.getoutline.com/s/hosting/doc/authentication-7KUQFF4z1M)
- [Outline Slack Integration](https://docs.getoutline.com/s/hosting/doc/slack-CWK9a9d67G)

### Files

- `modules/aws/apps/outline/main.tf` - Slack OAuth configuration
- `modules/aws/apps/outline/variables.tf` - `slack_client_id`, `slack_client_secret_arn`
- `environments/aws/dev/variables.tf` - `outline_slack_client_id`, `outline_slack_secret_arn`

---

## Outline First-Time Sign-In & Onboarding

**Date**: 2026-02-02

### What to Expect

When signing in to Outline for the first time:

1. **Login page shows "Sign in with Slack"** button (if button missing, wait for ECS deployment - see "ECS Deployment Timing" section)
2. **Click the button** → redirects to Slack for authorization
3. **Authorize in Slack** → grants Outline permission to read your identity
4. **Create workspace prompt** → Outline asks you to name your "workspace"
   - **This is confusing**: This is an Outline workspace, NOT your Slack workspace
   - Just enter a team/company name (e.g., "Almondbread")
5. **You're in** → First user is automatically admin

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| No Slack button on login page | ECS still deploying new task | Wait 2-5 minutes, refresh |
| "Invalid redirect_uri" error | Slack app misconfigured | Verify redirect URL is exactly `https://wiki.dev.almondbread.org/auth/slack.callback` |
| Slack auth succeeds but Outline errors | Missing OAuth scopes | Add `identity.avatar`, `identity.basic`, `identity.email`, `identity.team` to Slack app |
| "Workspace" confusion | Outline terminology | The "workspace" prompt is for Outline, not Slack - just name your team |

### After Sign-In

- **First user = Admin** - You can manage members, collections, and settings
- **Invite others** - Settings > Members > Invite (requires SMTP configured for email invites)
- **Create content** - Start creating Collections and Documents

---

## Outline SECRET_KEY Must Be Hexadecimal

**Date**: 2026-02-01

**Problem**: Outline container crashes on startup with:
```
Environment configuration is invalid, please check the following:
- SECRET_KEY must be a hexadecimal number
```

**Cause**: Outline requires `SECRET_KEY` and `UTILS_SECRET` to be hexadecimal strings (0-9, a-f characters only). Using `random_password` in Terraform generates alphanumeric strings (A-Z, a-z, 0-9) which includes invalid characters like 'g', 'h', 'G', etc.

**Solution**: Use `random_id` instead of `random_password`:

```hcl
# WRONG - generates alphanumeric (A-Z, a-z, 0-9)
resource "random_password" "secret_key" {
  length  = 64
  special = false
}

# CORRECT - generates hexadecimal (0-9, a-f)
resource "random_id" "secret_key" {
  byte_length = 32  # 32 bytes = 64 hex characters
}

# Use .hex attribute to get the hex string
secret_key = random_id.secret_key.hex
```

**Why this wasn't caught earlier**: The container starts, tries to parse the secret, fails validation, and exits with code 1. No stack trace, just a short validation error message. Easy to miss in log noise.

**Lesson**: Always check the exact format requirements for secrets. "64 character string" doesn't mean "any 64 characters".

---

## Zulip Cannot Run Self-Contained in ECS Fargate

**Date**: 2026-02-01

**Status**: ABANDONED ECS - Switched to EC2 VM deployment

### The Problem

Zulip fundamentally cannot run in ECS Fargate's single-container-per-task model. Multiple deployment approaches were attempted over 48+ hours, all failed:

1. **docker-zulip with PostgreSQL sidecar + external Redis** - Event workers crash continuously
2. **docker-zulip with internal PostgreSQL/Redis** - Database connection fails (supervisord can't manage multiple processes)
3. **docker-zulip with external RDS** - RDS cannot support custom hunspell dictionaries

### Why ECS Fargate Doesn't Work

**docker-zulip requires supervisord** to manage multiple internal services:
- PostgreSQL (or external RDS)
- Redis (or external ElastiCache)
- RabbitMQ
- Multiple Zulip event worker processes
- The main Zulip Django application

ECS Fargate runs containers with a single entrypoint. When docker-zulip tries to start supervisord to manage all these services, the container doesn't behave as expected:

1. **Internal PostgreSQL/Redis won't start**: Fargate doesn't support the process supervision model supervisord requires
2. **External RDS alternative fails**: Zulip requires custom hunspell dictionaries for full-text search. RDS is a managed service that doesn't allow installing custom files to the PostgreSQL filesystem
3. **Sidecar pattern fails**: Even with PostgreSQL as a separate sidecar container, Zulip's event workers crash in a continuous loop

### Attempted Solutions

| Approach | Outcome |
|----------|---------|
| docker-zulip + RDS + ElastiCache | RDS lacks hunspell dictionaries |
| docker-zulip + PostgreSQL sidecar | Event workers crash continuously |
| docker-zulip internal (all-in-one) | `Could not connect to database server. Exiting.` |
| Ephemeral storage | Doesn't solve the process supervision issue |
| EFS for persistence | Same core problem |

### The Solution: EC2 VM

Zulip's standard installation path assumes a VM where it can:
- Install and manage its own PostgreSQL with custom configurations
- Run supervisord to manage multiple services
- Install hunspell dictionaries system-wide
- Have full control over the operating system

The `modules/aws/apps/zulip-ec2/` module deploys Zulip on an EC2 instance using the standard Zulip installation script, which works as documented.

### Lessons Learned

1. **Not all apps are container-friendly**: Zulip is designed as a monolithic Python application with multiple co-located services
2. **ECS Fargate has limits**: Apps requiring process supervision (supervisord, systemd) don't map well to container orchestration
3. **RDS is managed, not configurable**: You cannot install custom extensions, dictionaries, or files on RDS
4. **Don't fight the architecture**: 48+ hours debugging proves it's faster to accept the VM pattern

### Files Removed

- `modules/aws/apps/zulip/` - ECS-based Zulip (PostgreSQL sidecar pattern)
- `modules/aws/apps/zulip-mini/` - ECS-based Zulip (all-in-one pattern)

### Files Added

- `modules/aws/apps/zulip-ec2/` - EC2-based Zulip with standard installation

---

## Zulip Mini Requires SECRETS_postgres_password (HISTORICAL)

**Date**: 2026-02-01

**Status**: HISTORICAL - Module has been removed. Kept for reference.

**Problem**: Zulip Mini container fails during bootstrap with:
```
/sbin/entrypoint.sh: line 360: SECRETS_postgres_password: parameter not set
```

**Cause**: The docker-zulip image requires `SECRETS_postgres_password` even when using internal PostgreSQL. The entrypoint script uses this password to configure the internal database. Without it, the script fails with a bash parameter expansion error.

**Solution**: Add `SECRETS_postgres_password` to the secrets passed to the container:
```hcl
# Generate postgres password
resource "random_password" "postgres_password" {
  length  = 32
  special = false
}

# Store in Secrets Manager
resource "aws_secretsmanager_secret_version" "secrets" {
  secret_string = jsonencode({
    secret_key        = random_password.secret_key.result
    postgres_password = random_password.postgres_password.result
  })
}

# Pass to container
secrets = {
  SECRETS_secret_key        = "${secret_arn}:secret_key::"
  SECRETS_postgres_password = "${secret_arn}:postgres_password::"
}
```

**Why this wasn't obvious**: The zulip-mini module was designed to use docker-zulip's internal PostgreSQL (no external RDS). The assumption was that internal PostgreSQL wouldn't need credentials passed in. But docker-zulip's entrypoint always expects `SECRETS_postgres_password` to set up the database, regardless of whether it's internal or external.

**Note**: This issue is moot - the entire ECS approach was abandoned. See "Zulip Cannot Run Self-Contained in ECS Fargate" above.

---

## SES Email Configuration

**Date**: 2026-02-02

### Overview

Multiple services use AWS SES for sending emails:
- **Outline**: Magic link authentication (primary auth method)
- **BookStack**: Email notifications (password resets, etc.)
- **Mattermost**: Email notifications
- **Zitadel**: User notifications

### Checking SES Status

**Check domain verification:**
```bash
./manual.sh ses_check_status
# Or directly:
aws-vault exec cochlearis --no-session -- aws ses get-identity-verification-attributes \
  --identities almondbread.org --region eu-central-1
```

**Check if in production mode (can send to anyone):**
```bash
aws-vault exec cochlearis --no-session -- aws ses get-account-sending-enabled --region eu-central-1
```

- `"Enabled": true` = **Production mode** - can send to any email address
- `"Enabled": false` = **Sandbox mode** - can only send to verified addresses

### If in Sandbox Mode

**Option 1**: Request production access:
```bash
./manual.sh ses_request_production
```

**Option 2**: Verify individual recipient emails for testing:
```bash
aws-vault exec cochlearis --no-session -- aws ses verify-email-identity \
  --email-address recipient@example.com --region eu-central-1
```

### Current Configuration

| Service | From Address | Used For |
|---------|-------------|----------|
| Outline | `wiki@almondbread.org` | Magic link login |
| BookStack | `docs@almondbread.org` | Notifications, password reset |
| Mattermost | `mm@almondbread.org` | Notifications |
| Zitadel | `noreply@almondbread.org` | User notifications |

### Troubleshooting

**Emails not arriving:**
1. Check SES sending mode (see above)
2. Check CloudWatch logs for the service
3. Verify the "From" domain is verified in SES
4. Check spam folders

**SES SMTP credentials:**
Each service has its own IAM user for SES SMTP. Credentials are stored in Secrets Manager:
- `cochlearis-dev-outline-ses-smtp-credentials-*`
- `cochlearis-dev-bookstack-ses-smtp-credentials-*`
- etc.

---

## ECS Deployment Timing After Terraform Apply

**Date**: 2026-02-02

**Problem**: After `terraform apply` completes successfully, new environment variables or configuration changes don't appear in the running application immediately.

**Cause**: Terraform updates the ECS task definition and triggers a service update, but ECS performs a **rolling deployment**. The old task(s) continue running until new task(s) are healthy. This can take 2-5 minutes depending on:
- Container startup time
- Health check intervals and thresholds
- Draining of connections from old tasks

**Symptoms**:
- Config changes show in AWS Console (task definition updated) but not in the app
- `terraform apply` shows "Apply complete!" but app behaves as before
- New environment variables visible in task definition but not in container

**Verification**:
```bash
# Check which task definition the service is currently using
aws-vault exec cochlearis --no-session -- aws ecs describe-services \
  --cluster cochlearis-dev-cluster --services SERVICE_NAME \
  --region eu-central-1 \
  --query 'services[0].taskDefinition'

# Check running vs desired count (should match when deployment is complete)
aws-vault exec cochlearis --no-session -- aws ecs describe-services \
  --cluster cochlearis-dev-cluster --services SERVICE_NAME \
  --region eu-central-1 \
  --query 'services[0].{running:runningCount,desired:desiredCount,deployments:length(deployments)}'
```

**Solution**: Wait for the deployment to complete. A deployment is finished when `runningCount` equals `desiredCount` and there's only 1 deployment (not 2).

**Force immediate deployment** (if needed):
```bash
aws-vault exec cochlearis --no-session -- aws ecs update-service \
  --cluster cochlearis-dev-cluster --service SERVICE_NAME \
  --force-new-deployment --region eu-central-1
```

**Note**: This issue is NOT a bug - it's how ECS rolling deployments work. The delay ensures zero-downtime deployments.

---

## Zulip EC2 Requires Swap Space

**Date**: 2026-02-02

**Problem**: Zulip installation fails on EC2 with:
```
No swap allocated; when running with < 5GB of RAM, we recommend at least 2GB of swap.
Zulip installation failed (exit code 1)!
```

**Cause**: Zulip installer requires swap space when running on instances with < 5GB RAM. The t3.medium instance has ~4GB RAM, triggering this check.

**Symptoms**:
- EC2 instance is running but ALB health checks fail
- `https://chat.dev.almondbread.org` returns 502/503 errors
- Installation log shows swap requirement error

**Solution**: The zulip-ec2 module's user_data script must create swap before running the Zulip installer:
```bash
# Create 2GB swap file
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

**Verification**:
```bash
# Check swap via SSM
aws-vault exec cochlearis --no-session -- aws ssm send-command \
  --instance-ids i-INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["free -h"]' \
  --region eu-central-1

# Check installation log
aws-vault exec cochlearis --no-session -- aws ssm send-command \
  --instance-ids i-INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["tail -50 /var/log/zulip-install.log"]' \
  --region eu-central-1
```

**Recovery**: After fixing the module, terminate the EC2 instance to trigger a fresh deployment:
```bash
aws-vault exec cochlearis --no-session -- aws ec2 terminate-instances \
  --instance-ids i-INSTANCE_ID --region eu-central-1

# Then re-apply terraform to create new instance with swap
cd environments/aws/dev && aws-vault exec cochlearis --no-session -- terraform apply
```

### Files

- `modules/aws/apps/zulip-ec2/main.tf` - user_data script with swap configuration

---

## Zulip EC2 Requires SSL Certificate Option

**Date**: 2026-02-02

**Problem**: Zulip installation fails with:
```
No SSL certificate found. One or both required files is missing:
    /etc/ssl/private/zulip.key
    /etc/ssl/certs/zulip.combined-chain.crt
```

**Cause**: The Zulip installer requires an SSL certificate option. When running behind an ALB (which handles TLS termination), you need to use `--self-signed-cert` to satisfy Zulip's internal requirements.

**Solution**: Add `--self-signed-cert` to the install command:
```bash
./scripts/setup/install --hostname="chat.dev.almondbread.org" --email="admin@example.com" --self-signed-cert
```

**Note**: This creates a self-signed certificate for Zulip's internal nginx. The ALB handles actual TLS termination for client connections, so users never see the self-signed cert.

### Files

- `modules/aws/apps/zulip-ec2/main.tf` - install command with --self-signed-cert

---

## Zulip Behind ALB/Reverse Proxy Configuration

**Date**: 2026-02-02

**Problem**: Zulip running behind an AWS ALB (or other reverse proxy) that terminates TLS requires proper configuration to trust proxy headers.

**Symptoms**:
- HTTP 500 errors with "Reverse proxy misconfiguration: No proxies configured in Zulip"
- ALB health checks fail
- Proxy detection middleware blocks requests

**Root Cause**: Zulip's nginx and Django middleware detect proxy headers (X-Forwarded-For, X-Forwarded-Proto) but don't trust them by default. This is a security feature to prevent header spoofing.

**Solution** (following vanilla Zulip docs at https://zulip.readthedocs.io/en/latest/production/reverse-proxies.html):

**Step 1**: Add load balancer configuration to `/etc/zulip/zulip.conf`:
```ini
[loadbalancer]
ips = 10.0.0.0/16  # Your VPC CIDR or specific ALB IPs
```

**Step 2**: Add settings to `/etc/zulip/settings.py`:
```python
EXTERNAL_HOST = "chat.dev.example.com"
ALLOWED_HOSTS = ["chat.dev.example.com"]

# Trust proxy headers
USE_X_FORWARDED_HOST = True
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')

# This is read by puppet for nginx config, and by Django for request validation
LOADBALANCER_IPS = ["10.0.0.0/16"]
```

**Step 3**: Regenerate nginx configuration using puppet:
```bash
/home/zulip/deployments/current/scripts/zulip-puppet-apply -f
```

**Step 4**: Restart Zulip:
```bash
su zulip -c '/home/zulip/deployments/current/scripts/restart-server'
```

**Key insight**: The nginx configuration is generated by puppet based on `/etc/zulip/zulip.conf`, not settings.py alone. The `[loadbalancer]` section in zulip.conf tells puppet to create nginx configs that trust the specified IPs.

**Reference**:
- Zulip reverse proxy docs: https://zulip.readthedocs.io/en/latest/production/reverse-proxies.html
- Implementation: `modules/aws/apps/zulip-ec2/main.tf`

---

## Zulip Realm Subdomain Routing

**Date**: 2026-02-03

**Problem**: When a Zulip realm is created with a subdomain (e.g., `cochlearis`), it's only accessible at `cochlearis.chat.dev.example.com`, not at the root domain `chat.dev.example.com`.

**Symptoms**:
- Root domain returns 404
- Realm only accessible at subdomain URL
- Users must know the subdomain to access Zulip

**Solution**: Use the `change_realm_subdomain` management command to move the realm to the root domain:

```bash
# List realms to find the realm ID
su zulip -c "/home/zulip/deployments/current/manage.py list_realms"

# Change subdomain to empty string for root domain access
su zulip -c "/home/zulip/deployments/current/manage.py change_realm_subdomain -r <realm_id> \"\""
```

**Note**: The realm ID can be numeric (e.g., `2`) or the string subdomain (e.g., `cochlearis`).

---

## Zulip Login Rate Limiting

**Date**: 2026-02-03

**Problem**: After multiple failed login attempts, Zulip rate-limits the user for ~25 minutes.

**Symptoms**:
- Error: "You're making too many attempts to sign in. Try again in X seconds"
- Even correct credentials won't work during lockout

**Solution**: Reset the authentication attempt counter:

```bash
su zulip -c "/home/zulip/deployments/current/manage.py reset_authentication_attempt_count -u user@example.com"
```

---

## Zulip Password Management

**Date**: 2026-02-03

**Problem**: The `change_password` command requires interactive input, which doesn't work via SSM.

**Solution**: Set passwords directly via Django shell:

```bash
# Create a Python script
cat > /tmp/setpw.py << 'EOF'
from zerver.models import UserProfile
from django.contrib.auth.hashers import make_password
u = UserProfile.objects.get(delivery_email="user@example.com")
u.password = make_password("NewPassword123")
u.save()
print(f"Password reset for {u.delivery_email}")
EOF

# Run via manage.py shell
su zulip -c "/home/zulip/deployments/current/manage.py shell < /tmp/setpw.py"
```

**Note**: Zulip stores two email fields - `delivery_email` (the real email) and `email` (internal format). Always use `delivery_email` for lookups.

---

## Azure AD OAuth Missing Client Secret Error

**Date**: 2026-02-03

**Problem**: Azure AD OAuth fails with "AADSTS70002: The provided request must include a 'client_secret' input parameter" even when the secret is configured in Zulip.

**Symptoms**:
- Azure AD login redirects back to Zulip login page
- Server logs show: `ERR [social] Request failed with 401: {"error":"invalid_client"}`
- Warning: `Your credentials aren't allowed`

**Root Cause**: The Azure AD app registration is missing the Zulip callback URL, or the app is not configured as a "Web" application.

**Solution**:
1. Go to Azure Portal > Microsoft Entra ID > App Registrations
2. Find your app by client ID
3. Under **Authentication**, ensure:
   - Platform is "Web" (not SPA or Mobile)
   - Redirect URI includes: `https://your-zulip-domain/complete/azuread-oauth2/`
4. Under **Certificates & secrets**, verify the client secret hasn't expired

**Expected callback URL format**: `https://chat.dev.almondbread.org/complete/azuread-oauth2/`

---

## Zulip Email Configuration (SES)

**Date**: 2026-02-03

**Problem**: Zulip requires email to be configured for user registration, password resets, and notifications. Without email, users cannot receive confirmation emails or invitations.

**Reference**: https://zulip.readthedocs.io/en/latest/production/email.html

**Solution**: The Zulip EC2 module supports AWS SES for email. Set `smtp_from_email` to enable:

```hcl
module "zulip_ec2" {
  # ... other config ...

  smtp_from_email = "chat@yourdomain.com"
  smtp_from_name  = "Zulip"
}
```

This creates an SES SMTP user and configures Zulip's `/etc/zulip/settings.py` and `/etc/zulip/zulip-secrets.conf`.

**Manual Configuration** (if not using Terraform):

1. Create SES SMTP credentials (IAM user with `ses:SendRawEmail`)
2. Add to `/etc/zulip/settings.py`:
```python
EMAIL_HOST = "email-smtp.eu-central-1.amazonaws.com"
EMAIL_HOST_USER = "your-smtp-username"
EMAIL_USE_TLS = True
EMAIL_PORT = 587
NOREPLY_EMAIL_ADDRESS = "noreply@yourdomain.com"
DEFAULT_FROM_EMAIL = "Zulip <chat@yourdomain.com>"
```
3. Add to `/etc/zulip/zulip-secrets.conf`:
```ini
email_password = your-smtp-password
```
4. Restart Zulip: `su zulip -c '/home/zulip/deployments/current/scripts/restart-server'`

**Note**: SES is in sandbox mode by default. Verify recipient emails or request production access (see "SES Sandbox Mode" gotcha).
