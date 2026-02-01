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

**Solutions** (in order of preference):
1. **Route53 Private Hosted Zone** (recommended): Create a private hosted zone in the VPC that resolves `auth.dev.almondbread.org` to the ALB's internal DNS name (not the public IP). This keeps traffic internal to the VPC.
   ```hcl
   resource "aws_route53_zone" "private" {
     name = "dev.almondbread.org"
     vpc {
       vpc_id = aws_vpc.main.id
     }
   }

   resource "aws_route53_record" "auth_private" {
     zone_id = aws_route53_zone.private.zone_id
     name    = "auth.dev.almondbread.org"
     type    = "A"
     alias {
       name                   = aws_lb.main.dns_name
       zone_id                = aws_lb.main.zone_id
       evaluate_target_health = true
     }
   }
   ```

2. **Service Discovery** (alternative): Use AWS Cloud Map service discovery for internal service-to-service communication. Configure apps to use internal endpoints like `zitadel.cochlearis.internal` instead of public URLs.

3. **Split Horizon DNS**: Different DNS responses for internal vs external queries.

**Note**: This issue affects any scenario where ECS services need to call each other through the public load balancer. For ECS-to-ECS communication, prefer internal networking.

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
