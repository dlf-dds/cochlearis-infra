# Infrastructure Recipe

A first-principles guide to building the **Almondbread Collaboration Services** infrastructure from scratch. This document explains the design patterns, architecture decisions, and implementation approach so the same system can be recreated for a different cloud account without copying specific code.

> **Note:** This repo currently deploys to the `cochlearis` AWS account. To adapt for another account, update the `project` variable and backend configuration.

---

## Philosophy

### Core Principles

1. **Infrastructure as Code** - All infrastructure is defined in Terraform, version controlled, and reproducible
2. **Environment Parity** - Dev, staging, and prod share the same architecture with different configurations
3. **Module Reusability** - Common patterns extracted into reusable modules
4. **Governance by Default** - Cost controls, lifecycle management, and tagging enforced automatically
5. **Least Privilege** - No long-lived credentials; temporary tokens and OIDC everywhere

### Design Patterns

| Pattern | Application |
|---------|-------------|
| **Layered Modules** | Infrastructure modules (VPC, ECS) → App modules (Zitadel, Zulip) → Environments |
| **Composition over Inheritance** | App modules compose infrastructure modules rather than extending them |
| **Convention over Configuration** | Sensible defaults with override capability |
| **Fail-Safe Defaults** | Deletion protection on by default for prod, off for dev |

---

## Directory Structure

```
repository/
├── environments/           # Environment-specific configurations
│   └── {cloud}/           # aws, gcp, azure
│       └── {env}/         # dev, staging, prod
│           ├── main.tf    # Module composition
│           ├── variables.tf
│           ├── outputs.tf
│           ├── providers.tf
│           └── terraform.tfvars
├── modules/
│   └── {cloud}/
│       ├── {resource}/    # Infrastructure modules (vpc, ecs-cluster, rds-postgres)
│       └── apps/          # Application modules (zitadel, zulip, bookstack)
│           └── {app}/
└── scripts/               # Utility scripts (bootstrap, format, docs)
```

### Why This Structure?

- **Cloud-namespaced modules**: Allows multi-cloud without naming conflicts
- **Environments separate from modules**: Same modules, different configs
- **Apps as composite modules**: Each app bundles its infrastructure (DB, cache, storage, service)

---

## Module Architecture

### Layer 1: Infrastructure Modules

These are the building blocks. Each does one thing well.

#### VPC Module
**Purpose**: Network foundation with public/private subnet segregation

**Inputs**:
- Project name, environment
- CIDR block for VPC
- Availability zones (list)
- Public subnet CIDRs (list)
- Private subnet CIDRs (list)
- NAT gateway options (enable, single vs per-AZ)

**Resources**:
- VPC with DNS support enabled
- Internet Gateway
- Public subnets (one per AZ) with route to IGW
- Private subnets (one per AZ)
- NAT Gateway(s) in public subnets
- Route tables with appropriate routes
- S3 VPC endpoint (gateway type, free)

**Outputs**: VPC ID, subnet IDs (public/private), route table IDs

**Design Decision**: Private subnets for all workloads, public only for load balancers and NAT.

#### ECS Cluster Module
**Purpose**: Container orchestration foundation

**Inputs**:
- Project, environment
- VPC ID, private subnet IDs

**Resources**:
- ECS Cluster with Container Insights enabled
- Task execution IAM role (for ECR pull, CloudWatch logs)
- Task IAM role (for application permissions)
- Security group for tasks (egress only by default)

**Outputs**: Cluster ID/name, role ARNs/names, security group ID

**Design Decision**: Fargate-only (no EC2 capacity providers) for simplicity and serverless scaling.

#### ECS Service Module
**Purpose**: Reusable service deployment pattern

**Inputs**:
- Cluster ID, VPC ID, subnet IDs, security groups
- Container image, port, CPU, memory
- Environment variables (map), secrets (map of ARNs)
- Optional: command override, health check config
- ALB integration: listener ARN, host header, health check path
- Sidecar containers (list of container definitions)
- EFS volumes (list of volume configurations)

**Resources**:
- CloudWatch log group
- Task definition with container definition(s)
- Target group (if ALB integration enabled)
- Listener rule for host-based routing
- ECS service with deployment circuit breaker

**Key Implementation Details**:
- Secrets use Secrets Manager ARN format: `arn:...:secret-name:json-key::`
- Container command passed via `command` field in container definition (for images requiring args)
- Health check supports ALB health check (HTTP) and container health check (CMD)

**Sidecar Container Pattern**:
```hcl
sidecar_containers = [
  {
    name      = "postgres"
    image     = "postgres:14"
    port      = 5432
    essential = true
    environment_variables = {
      POSTGRES_USER     = "zulip"
      POSTGRES_PASSWORD = "..."
    }
    health_check = {
      command      = ["CMD-SHELL", "pg_isready -U zulip"]
      interval     = 30
      timeout      = 5
      retries      = 3
      start_period = 60
    }
    mount_points = [
      {
        volume_name    = "postgres-data"
        container_path = "/var/lib/postgresql/data"
      }
    ]
  }
]

efs_volumes = [
  {
    name            = "postgres-data"
    file_system_id  = module.efs.file_system_id
    access_point_id = module.efs.access_point_ids["postgres"]
    container_path  = "/var/lib/postgresql/data"
  }
]
```

The main container can use `depends_on` with condition `HEALTHY` to wait for the sidecar.

#### ALB Module
**Purpose**: Shared application load balancer for all services

**Inputs**:
- VPC ID, public subnet IDs
- Default certificate ARN

**Resources**:
- Application Load Balancer (internet-facing)
- Security group (443 inbound from anywhere, egress to VPC)
- HTTP listener (redirect to HTTPS)
- HTTPS listener with default certificate

**Outputs**: ALB DNS name, zone ID, listener ARNs, security group ID

**Design Decision**: Single ALB shared across services using host-based routing. Cost-effective and simplifies DNS/certificate management.

#### RDS PostgreSQL/MySQL Modules
**Purpose**: Managed relational databases

**Inputs**:
- Identifier, database name
- Instance class, storage settings
- Multi-AZ, deletion protection, backup settings
- Allowed security group IDs (for ingress rules)

**Resources**:
- DB subnet group
- Security group with ingress from allowed SGs only
- Random password generation
- Secrets Manager secret (JSON: username, password, host, port, database)
- RDS instance with encryption enabled

**Outputs**: Endpoint, address, port, database name, username, secret ARN

**Design Decision**: Password stored in Secrets Manager as JSON for ECS secret injection compatibility.

#### ElastiCache Redis Module
**Purpose**: Managed Redis for session/cache

**Inputs**: Similar pattern to RDS

**Resources**:
- Subnet group
- Security group
- Replication group (single node for dev, multi-node for prod)

**Design Decision**: Replication group even for single node - allows scaling without replacement.

#### EFS Module
**Purpose**: Persistent storage for containers (required for sidecar databases)

**Inputs**:
- Project, environment
- VPC ID, private subnet IDs
- Access point configurations (path, POSIX user/group)
- Allowed security group IDs

**Resources**:
- EFS file system with encryption enabled
- Mount targets in each private subnet
- Security group for NFS (port 2049)
- Access points for container-specific paths

**Outputs**: File system ID, access point IDs, security group ID

**Design Decision**: Access points provide isolation between containers sharing the same EFS.

**Warning**: EFS has no built-in backup. Add AWS Backup plan for production use.

#### ACM Certificate Module
**Purpose**: TLS certificates with DNS validation

**Inputs**: Domain name, Route53 zone ID

**Resources**:
- ACM certificate request
- Route53 validation records
- Certificate validation resource (waits for validation)

**Outputs**: Certificate ARN, validated certificate ARN

**Design Decision**: DNS validation over email - fully automated, no human intervention.

#### SES SMTP User Module
**Purpose**: Email sending credentials

**Resources**:
- IAM user with SES send policy
- Access key
- Secrets Manager secret for SMTP credentials

**Note**: SES SMTP password requires specific derivation from secret key (AWS-specific algorithm).

### Layer 2: Application Modules

These compose infrastructure modules into complete application stacks.

#### Pattern: Application Module Structure

Each app module follows this pattern:

```hcl
# 1. Locals for naming and domain
locals {
  name_prefix = "${var.project}-${var.environment}"
  domain      = "{subdomain}.${var.environment}.${var.domain_name}"
}

# 2. SSL Certificate (or accept pre-created)
module "certificate" { ... }

# 3. DNS Record pointing to ALB
resource "aws_route53_record" { ... }

# 4. Database(s)
module "database" { ... }

# 5. Cache (if needed)
module "redis" { ... }

# 6. Object Storage (if needed)
resource "aws_s3_bucket" { ... }

# 7. Secrets
resource "aws_secretsmanager_secret" { ... }

# 8. IAM Policies (secrets access, S3 access)
resource "aws_iam_role_policy" { ... }

# 9. Security Group Rules (ALB -> container port)
resource "aws_security_group_rule" { ... }

# 10. ECS Service
module "service" { ... }
```

#### Zitadel (Identity Provider)
**Domain**: `auth.{env}.{domain}`
**Components**: PostgreSQL, ECS service
**Container Requirements**:
- Command: `["start-from-init"]` (required - image has no default command)
- Master key: 32-char random, stored as JSON `{"key": "..."}`, accessed via `:key::`
- Port: 8080 (HTTP internally)
- Health check: `/debug/healthz`

**Environment Variables Pattern**:
```
ZITADEL_DATABASE_POSTGRES_HOST
ZITADEL_DATABASE_POSTGRES_PORT
ZITADEL_DATABASE_POSTGRES_DATABASE
ZITADEL_DATABASE_POSTGRES_USER
ZITADEL_DATABASE_POSTGRES_SSL_MODE=require
ZITADEL_EXTERNALSECURE=true
ZITADEL_EXTERNALDOMAIN={domain}
ZITADEL_EXTERNALPORT=443
```

#### Zulip (Chat)
**Domain**: `chat.{env}.{domain}`
**Components**: PostgreSQL, Redis, S3, SES, ECS service
**Container Requirements**:
- Port: 80 (with `DISABLE_HTTPS=true`, ALB handles TLS)
- Needs `SSL_CERTIFICATE_GENERATION=auto` even when HTTPS disabled
- Health check: `/health`

**Secrets Pattern**:
```
SECRETS_postgres_password={db_secret_arn}:password::
SECRETS_secret_key={app_secret_arn}:secret_key::
```

#### BookStack (Documentation)
**Domain**: `docs.{env}.{domain}`
**Components**: MySQL (required - no PostgreSQL support), S3, ECS service
**Container Requirements**:
- Port: 80
- Laravel app key format: `base64:{32-char-key}`
- Health check: `/status`

**OIDC Configuration** (for SSO):
```
AUTH_METHOD=oidc
OIDC_ISSUER=https://auth.{env}.{domain}
OIDC_ISSUER_DISCOVER=true
```

#### Mattermost (Team Chat)
**Domain**: `mm.{env}.{domain}`
**Components**: PostgreSQL, ECS service
**Container Requirements**:
- Port: 8065
- Health check: `/api/v4/system/ping`
- ARM64 compatible (unlike Zulip)

**Database Configuration**:
- Mattermost requires a full DSN connection string
- Store complete DSN in Secrets Manager: `postgres://user:pass@host:port/db?sslmode=require`
- Reference as single secret (not JSON extraction)

**OIDC Configuration** (for SSO via GitLab adapter):
```
MM_GITLABSETTINGS_ENABLE=true
MM_GITLABSETTINGS_ID={client_id}
MM_GITLABSETTINGS_SECRET={client_secret}
MM_GITLABSETTINGS_AUTHENDPOINT=https://auth.{env}.{domain}/oauth/v2/authorize
MM_GITLABSETTINGS_TOKENENDPOINT=https://auth.{env}.{domain}/oauth/v2/token
MM_GITLABSETTINGS_USERAPIENDPOINT=https://auth.{env}.{domain}/oidc/v1/userinfo
```

**Note**: Mattermost Team Edition doesn't support generic OIDC. The GitLab adapter works with Zitadel because Zitadel's userinfo endpoint returns compatible fields.

#### Zulip - Sidecar Container Pattern

Zulip requires PostgreSQL with full-text search dictionaries (hunspell). AWS RDS doesn't support custom dictionaries, so we use a **sidecar container pattern**:

```
┌─────────────────────────────────────────────────┐
│                  ECS Task                        │
│  ┌─────────────┐      ┌──────────────────────┐  │
│  │   Zulip     │─────▶│  PostgreSQL Sidecar  │  │
│  │  (port 80)  │      │    (port 5432)       │  │
│  └─────────────┘      └──────────────────────┘  │
│         │                       │               │
│         ▼                       ▼               │
│    ALB Target              EFS Volume           │
│                        (data persistence)       │
└─────────────────────────────────────────────────┘
```

**Implementation**:
- Main container: `zulip/docker-zulip` on port 80
- Sidecar: `postgres:14` with hunspell dictionaries
- EFS volume mounted to `/var/lib/postgresql/data`
- Sidecar marked as `essential: true` with health check
- Main container `depends_on` sidecar with `HEALTHY` condition

**Warning**: EFS has no automatic backups. See [PHOENIX.md](PHOENIX.md) for data persistence gaps.

### Layer 3: Governance Module

**Purpose**: Automated cost control and resource lifecycle management

**Components**:

1. **SNS Topic**: Central notification hub for all alerts

2. **Budget Alerts**: AWS Budgets with thresholds at 50%, 80%, 100%, 120%

3. **Lifecycle Lambda**:
   - Triggered daily by EventBridge
   - Scans resources for `Lifecycle` and `ExpiresAt` tags
   - Sends warnings at N days, terminates at M days (if enabled)
   - Generates weekly cost reports

4. **Cost Reports**: EventBridge rule triggers Lambda weekly for spend summary

**Tag Strategy**:
| Tag | Purpose |
|-----|---------|
| `Project` | Cost allocation |
| `Environment` | Deployment stage |
| `Owner` | Alert recipient |
| `ManagedBy` | `terraform` |
| `Lifecycle` | `persistent` or `temporary` |
| `ExpiresAt` | ISO 8601 expiration date |

**Implementation**: Use AWS provider `default_tags` to apply mandatory tags to all resources automatically.

---

## Environment Configuration

### Provider Setup

```hcl
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      Owner       = var.owner_email
      ManagedBy   = "terraform"
      Lifecycle   = "persistent"  # Override per-resource for temporary
    }
  }
}
```

### Backend Configuration

```hcl
terraform {
  backend "s3" {
    bucket         = "{project}-terraform-state"
    key            = "{env}/terraform.tfstate"
    region         = "{region}"
    dynamodb_table = "{project}-terraform-locks"
    encrypt        = true
  }
}
```

### Environment Differentiation

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| `db_instance_class` | t3.micro | t3.small | t3.medium+ |
| `db_multi_az` | false | false | true |
| `deletion_protection` | false | true | true |
| `skip_final_snapshot` | true | false | false |
| `desired_count` | 1 | 1 | 2+ |
| `monthly_budget` | $200 | $500 | as needed |

---

## Security Patterns

### Credential Management

**Local Development**:
- AWS: `aws-vault` with STS temporary credentials
- Use `--no-session` flag for IAM operations (avoids regional STS token issues)
- GCP: `gcloud auth application-default login`
- Azure: `az login`

**CI/CD**:
- AWS: OIDC with IAM roles (GitHub Actions -> AssumeRoleWithWebIdentity)
- GCP: Workload Identity Federation
- Azure: OIDC with Service Principal

**Application Secrets**:
- All secrets in Secrets Manager (not environment variables)
- ECS pulls secrets at task start via `secrets` block
- JSON format for multi-value secrets: `{"key": "value"}`
- Reference format: `{secret_arn}:{json_key}::{version_stage}`

### Network Security

```
Internet
    │
    ▼
┌───────────────────────┐
│   ALB (public subnet) │  ← Only 443 inbound
└───────────────────────┘
    │
    ▼ (HTTP 80/8080 internal)
┌───────────────────────┐
│  ECS Tasks (private)  │  ← Only ALB SG allowed
└───────────────────────┘
    │
    ▼
┌───────────────────────┐
│  RDS/Redis (private)  │  ← Only ECS SG allowed
└───────────────────────┘
```

---

## Local Development

The `local/` directory provides a Docker Compose stack that mirrors the AWS deployment for local testing.

```bash
cd local
make up          # Start all services
make logs        # View logs
make down        # Stop all services
```

**Services available locally**:
- Zitadel: http://localhost:8080
- BookStack: http://localhost:6875
- Mattermost: http://localhost:8065

**Note**: Zulip is excluded from local development because it has no ARM64 image. Use Mattermost for chat testing on Apple Silicon.

---

## Bootstrap Process

### 1. Create Terraform State Backend

```bash
./scripts/bootstrap-aws
```

This creates the S3 bucket and DynamoDB table for state locking.

### 2. Configure DNS

Create Route53 hosted zone for your domain and note the zone ID.

### 3. Create terraform.tfvars

Copy the example file and fill in values:

```bash
cd environments/aws/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 4. Initial Terraform Apply

```bash
aws-vault exec {profile} --duration=2h
terraform init
terraform plan
terraform apply
```

This takes 15-20 minutes for initial creation.

### 5. Configure Zitadel OIDC (Manual Step Required)

After Zitadel is running, you must manually create a service account for OIDC automation:

1. Log into Zitadel: `https://auth.{env}.{domain}/ui/console`
2. Username: `admin@zitadel.auth.{env}.{domain}`
3. Get password from Secrets Manager:
   ```bash
   aws secretsmanager get-secret-value \
     --secret-id {project}-{env}-zitadel-master-key \
     --query 'SecretString' --output text | jq -r '.admin_password'
   ```
4. Create service user: Organization → Service Users → +New
5. Name: "terraform-bootstrap", grant **ORG_OWNER** role
6. Create Personal Access Token (PAT) and save it

Then run the bootstrap script:

```bash
ZITADEL_PAT="your-token" ./bootstrap-zitadel-oidc.sh
```

Finally, apply with OIDC enabled:

```bash
terraform apply -var="enable_zitadel_oidc=true"
```

### 6. Verify SES (If Using Email)

SES requires domain verification and production access request for sending emails.

---

## Common Issues and Solutions

### Circular Dependencies
**Problem**: ALB needs certificate, certificate module needs ALB for validation
**Solution**: Create primary certificate in environment's main.tf before ALB, pass ARN to both

### ECS Container Won't Start
**Debug**: Check CloudWatch logs at `/ecs/{cluster}/{service}`
**Common causes**:
- Missing command for images without default CMD (Zitadel needs `start-from-init`)
- Secrets not accessible (check IAM policy includes secret ARN)
- Wrong secret format (plain text vs JSON extraction)

### IAM InvalidClientTokenId Errors
**Cause**: STS regional tokens rejected by IAM global endpoint
**Solution**: Use `aws-vault exec {profile} --no-session` for Terraform operations creating IAM resources

### Database Driver Not Found
**Cause**: Application image doesn't have driver for your database type
**Solution**: Check application requirements (BookStack = MySQL only, most others = PostgreSQL)

---

## Extending the Pattern

### Adding a New Application

1. Create module at `modules/aws/apps/{app-name}/`
2. Follow the application module pattern (certificate, DNS, DB, service)
3. Add to environment's main.tf with environment-specific config
4. Add outputs to environment's outputs.tf

### Adding a New Environment

1. Copy existing environment directory
2. Update terraform.tfvars with environment-specific values
3. Update backend configuration for new state file
4. Run terraform init and apply

### Adding a New Cloud Provider

1. Create `modules/{cloud}/` directory
2. Implement equivalent infrastructure modules
3. Create `environments/{cloud}/{env}/` directories
4. Document cloud-specific patterns in this file

---

## Testing Checklist

Before marking infrastructure complete:

**Basic Functionality**:
- [ ] All services return 200 on health endpoints
- [ ] DNS resolves correctly for all domains
- [ ] TLS certificates valid and not expiring soon
- [ ] Secrets Manager secrets populated
- [ ] CloudWatch logs receiving container output

**SSO Integration**:
- [ ] Can log into Zitadel admin console
- [ ] OIDC clients created for each service
- [ ] Can log into BookStack via Zitadel SSO
- [ ] Can log into Mattermost via Zitadel SSO
- [ ] Can log into Zulip via Zitadel SSO

**Governance**:
- [ ] Budget alerts configured
- [ ] SNS subscription confirmed (check email)
- [ ] All resources have required tags

**Operations**:
- [ ] Can SSH tunnel to RDS for debugging
- [ ] Terraform plan shows no changes (idempotent)
- [ ] Local Docker Compose stack starts successfully

**Phoenix Readiness** (see [PHOENIX.md](PHOENIX.md)):
- [ ] RDS automated backups enabled
- [ ] EFS backup plan configured (if using sidecar Postgres)
- [ ] S3 versioning enabled on upload buckets
- [ ] Encryption keys protected with lifecycle ignore

---

## Cost Optimization Notes

1. **Single NAT Gateway** in dev/staging (multi-AZ NAT in prod only)
2. **Single ALB** shared across all services (not one per service)
3. **t3 instances** with burstable baseline (not t2)
4. **gp3 storage** (better price/performance than gp2)
5. **S3 VPC endpoint** (free, reduces NAT traffic)
6. **Fargate Spot** for non-critical workloads (up to 70% savings)
7. **Reserved capacity** for prod databases (1-year commitment = 30-40% savings)

---

## Related Documentation

- [README.md](../README.md) - Quick start and overview
- [EXCELLENCE.md](EXCELLENCE.md) - Principles and philosophy behind this repository
- [PHOENIX.md](PHOENIX.md) - Gap analysis for destroy/rebuild capability
- [GOTCHAS.md](GOTCHAS.md) - Troubleshooting and lessons learned
- Module READMEs - Auto-generated via `terraform-docs`
