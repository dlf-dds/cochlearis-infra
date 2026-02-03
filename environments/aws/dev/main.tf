# Dev environment - cochlearis-infra

# =============================================================================
# Core Infrastructure
# =============================================================================

module "vpc" {
  source = "../../../modules/aws/vpc"

  project     = var.project
  environment = var.environment

  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

module "ecs" {
  source = "../../../modules/aws/ecs-cluster"

  project     = var.project
  environment = var.environment

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # ALB ingress rules (centralized to avoid duplicate rules from app modules)
  alb_security_group_id = module.alb.security_group_id
  alb_ingress_ports     = [80, 3000, 8065, 8080] # 80 for BookStack/Docusaurus, 3000 for Outline, 8065 for Mattermost, 8080 for Zitadel

  # Internal ALB ingress rules (for service-to-service communication)
  internal_alb_security_group_id = module.alb_internal.security_group_id
  internal_alb_ingress_ports     = [8080] # 8080 for Zitadel internal access
}

# Primary SSL certificate (for ALB default - using auth domain)
module "primary_certificate" {
  source = "../../../modules/aws/acm-certificate"

  project     = var.project
  environment = var.environment
  domain_name = "auth.${var.environment}.${var.domain_name}"
  zone_id     = var.route53_zone_id
}

# Shared ALB for all services (internet-facing for user traffic)
module "alb" {
  source = "../../../modules/aws/alb"

  project         = var.project
  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.public_subnet_ids
  certificate_arn = module.primary_certificate.validation_certificate_arn
  internal        = false
}

# Internal ALB for service-to-service communication (OIDC, etc.)
# This solves the hairpin NAT issue - services can reach each other directly
module "alb_internal" {
  source = "../../../modules/aws/alb"

  project             = var.project
  environment         = var.environment
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  certificate_arn     = module.primary_certificate.validation_certificate_arn
  internal            = true
  name_suffix         = "internal"
  allowed_cidr_blocks = ["10.0.0.0/16"] # VPC CIDR only
}

# =============================================================================
# ECR Repositories for Container Images
# =============================================================================
# Mirrors Docker Hub images to avoid rate limits (429 Too Many Requests).
# After applying, run: ./scripts/sync-images-to-ecr.sh

module "ecr" {
  source = "../../../modules/aws/ecr"

  # Zulip ECR repos removed - using standard installation on EC2, not docker-zulip
  repositories = {
    "bookstack"  = { source = "linuxserver/bookstack:latest" }
    "mattermost" = { source = "mattermost/mattermost-team-edition:latest" }
    "outline"    = { source = "outlinewiki/outline:latest" }
    "zitadel"    = { source = "ghcr.io/zitadel/zitadel:latest" }
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# =============================================================================
# Private DNS Zone for Internal Service-to-Service Communication
# =============================================================================
# Resolves auth.dev.almondbread.org to INTERNAL ALB within the VPC.
# This is the key to solving hairpin NAT - apps calling Zitadel for OIDC
# discovery get routed to the internal ALB which has private IPs.

resource "aws_route53_zone" "private" {
  name = "${var.environment}.${var.domain_name}"

  vpc {
    vpc_id = module.vpc.vpc_id
  }

  tags = {
    Name        = "${var.project}-${var.environment}-private-zone"
    Environment = var.environment
  }
}

# Auth domain points to INTERNAL ALB (this is what apps use for OIDC)
resource "aws_route53_record" "auth_private" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "auth.${var.environment}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.alb_internal.alb_dns_name
    zone_id                = module.alb_internal.alb_zone_id
    evaluate_target_health = true
  }
}

# =============================================================================
# Internal ALB Target Group for Zitadel
# =============================================================================
# Separate target group for the internal ALB (AWS doesn't allow sharing TGs across ALBs)

resource "aws_lb_target_group" "zitadel_internal" {
  name             = "${var.project}-${var.environment}-zitadel-int"
  port             = 8080
  protocol         = "HTTP"
  protocol_version = "HTTP2" # Required for gRPC/Terraform provider
  vpc_id           = module.vpc.vpc_id
  target_type      = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/debug/healthz"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project}-${var.environment}-zitadel-internal"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener_rule" "zitadel_internal" {
  listener_arn = module.alb_internal.https_listener_arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.zitadel_internal.arn
  }

  condition {
    host_header {
      values = ["auth.${var.environment}.${var.domain_name}"]
    }
  }
}

# =============================================================================
# Applications
# =============================================================================

module "zitadel" {
  source = "../../../modules/aws/apps/zitadel"

  project         = var.project
  environment     = var.environment
  region          = var.region
  domain_name     = var.domain_name
  route53_zone_id = var.route53_zone_id

  # Use the pre-created certificate (avoids circular dependency with ALB)
  create_certificate = false
  certificate_arn    = module.primary_certificate.validation_certificate_arn

  # Network
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # ALB
  alb_dns_name          = module.alb.alb_dns_name
  alb_zone_id           = module.alb.alb_zone_id
  alb_listener_arn      = module.alb.https_listener_arn
  alb_security_group_id = module.alb.security_group_id

  # ECS
  ecs_cluster_id              = module.ecs.cluster_id
  ecs_tasks_security_group_id = module.ecs.tasks_security_group_id
  task_execution_role_arn     = module.ecs.task_execution_role_arn
  task_execution_role_name    = module.ecs.task_execution_role_name
  task_role_arn               = module.ecs.task_role_arn

  # Dev-specific configuration
  db_instance_class      = "db.t3.micro"
  db_multi_az            = false
  db_deletion_protection = false
  db_skip_final_snapshot = true
  ecs_cpu                = 512
  ecs_memory             = 1024

  # Email configuration (SES)
  smtp_from_email = "noreply@${var.domain_name}"
  smtp_from_name  = "Cochlearis Auth"

  # Register with internal ALB for service-to-service OIDC discovery
  additional_target_group_arns = [aws_lb_target_group.zitadel_internal.arn]

  # Use ECR image to avoid Docker Hub rate limits
  container_image = "${module.ecr.repository_urls["zitadel"]}:latest"
}

# =============================================================================
# Zitadel OIDC Configuration (ABANDONED - see OIDC.md)
# =============================================================================
# OIDC via self-hosted Zitadel was attempted for 48 hours but never worked.
# Kept for future reference. Use Google OAuth instead (see terraform.tfvars).
#
# If retrying: OIDC apps are created in dev/oidc/ Terraform root to avoid
# chicken-and-egg with the zitadel provider. That root writes config to SSM.

data "aws_ssm_parameter" "oidc_issuer" {
  count = var.enable_zitadel_oidc ? 1 : 0
  name  = "/${var.project}/${var.environment}/oidc/issuer-url"
}

data "aws_ssm_parameter" "bookstack_oidc_client_id" {
  count = var.enable_zitadel_oidc ? 1 : 0
  name  = "/${var.project}/${var.environment}/oidc/bookstack/client-id"
}

data "aws_ssm_parameter" "bookstack_oidc_secret_arn" {
  count = var.enable_zitadel_oidc ? 1 : 0
  name  = "/${var.project}/${var.environment}/oidc/bookstack/secret-arn"
}

data "aws_ssm_parameter" "mattermost_oidc_client_id" {
  count = var.enable_zitadel_oidc ? 1 : 0
  name  = "/${var.project}/${var.environment}/oidc/mattermost/client-id"
}

data "aws_ssm_parameter" "mattermost_oidc_secret_arn" {
  count = var.enable_zitadel_oidc ? 1 : 0
  name  = "/${var.project}/${var.environment}/oidc/mattermost/secret-arn"
}

data "aws_ssm_parameter" "zulip_oidc_client_id" {
  count = var.enable_zitadel_oidc ? 1 : 0
  name  = "/${var.project}/${var.environment}/oidc/zulip/client-id"
}

data "aws_ssm_parameter" "zulip_oidc_secret_arn" {
  count = var.enable_zitadel_oidc ? 1 : 0
  name  = "/${var.project}/${var.environment}/oidc/zulip/secret-arn"
}

data "aws_ssm_parameter" "outline_oidc_client_id" {
  count = var.enable_zitadel_oidc ? 1 : 0
  name  = "/${var.project}/${var.environment}/oidc/outline/client-id"
}

data "aws_ssm_parameter" "outline_oidc_secret_arn" {
  count = var.enable_zitadel_oidc ? 1 : 0
  name  = "/${var.project}/${var.environment}/oidc/outline/secret-arn"
}

# =============================================================================
# ALB OIDC Authentication (for Docusaurus)
# =============================================================================
# Fetch OAuth client secrets from Secrets Manager for ALB-level authentication.
# Azure AD takes priority if configured, otherwise Google OAuth is used.

data "aws_secretsmanager_secret_version" "azure_oauth" {
  count     = var.enable_azure_oauth && var.enable_docusaurus_auth ? 1 : 0
  secret_id = var.azure_client_secret_arn
}

data "aws_secretsmanager_secret_version" "google_oauth" {
  count     = var.enable_google_oauth && !var.enable_azure_oauth && var.enable_docusaurus_auth ? 1 : 0
  secret_id = var.google_oauth_secret_arn
}

locals {
  # Determine which OAuth provider to use for ALB OIDC (Azure AD takes priority)
  use_azure_oidc  = var.enable_azure_oauth && var.enable_docusaurus_auth
  use_google_oidc = var.enable_google_oauth && !var.enable_azure_oauth && var.enable_docusaurus_auth

  # Azure AD OIDC endpoints
  azure_oidc_config = local.use_azure_oidc ? {
    authorization_endpoint = "https://login.microsoftonline.com/${var.azure_tenant_id}/oauth2/v2.0/authorize"
    client_id              = var.azure_client_id
    client_secret          = jsondecode(data.aws_secretsmanager_secret_version.azure_oauth[0].secret_string)["client_secret"]
    issuer                 = "https://login.microsoftonline.com/${var.azure_tenant_id}/v2.0"
    token_endpoint         = "https://login.microsoftonline.com/${var.azure_tenant_id}/oauth2/v2.0/token"
    user_info_endpoint     = "https://graph.microsoft.com/oidc/userinfo"
    scope                  = "openid email profile"
    session_timeout        = 604800 # 7 days
  } : null

  # Google OIDC endpoints
  google_oidc_config = local.use_google_oidc ? {
    authorization_endpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    client_id              = var.google_oauth_client_id
    client_secret          = jsondecode(data.aws_secretsmanager_secret_version.google_oauth[0].secret_string)["client_secret"]
    issuer                 = "https://accounts.google.com"
    token_endpoint         = "https://oauth2.googleapis.com/token"
    user_info_endpoint     = "https://openidconnect.googleapis.com/v1/userinfo"
    scope                  = "openid email profile"
    session_timeout        = 604800 # 7 days
  } : null

  # Use whichever OIDC config is active
  docusaurus_oidc_config = local.use_azure_oidc ? local.azure_oidc_config : local.google_oidc_config
}

# =============================================================================
# Zulip EC2 - VM-based deployment (ECS Fargate not suitable)
# =============================================================================
# See gotchas.md "Zulip Cannot Run Self-Contained in ECS Fargate" for details.
# Using EC2 with standard Zulip installation instead of docker-zulip.
#
# URL: https://chat.dev.almondbread.org

module "zulip_ec2" {
  source = "../../../modules/aws/apps/zulip-ec2"

  project         = var.project
  environment     = var.environment
  region          = var.region
  domain_name     = var.domain_name
  route53_zone_id = var.route53_zone_id

  # Network
  vpc_id            = module.vpc.vpc_id
  private_subnet_id = module.vpc.private_subnet_ids[0]
  public_subnet_id  = module.vpc.public_subnet_ids[0]

  # ALB
  alb_dns_name          = module.alb.alb_dns_name
  alb_zone_id           = module.alb.alb_zone_id
  alb_listener_arn      = module.alb.https_listener_arn
  alb_security_group_id = module.alb.security_group_id

  # Configuration
  instance_type = "t3.medium" # 2 vCPU, 4GB RAM - sufficient for ~100 users
  admin_email   = var.owner_email

  # Azure AD OAuth
  azure_tenant_id         = var.enable_azure_oauth ? var.azure_tenant_id : ""
  azure_client_id         = var.enable_azure_oauth ? var.azure_client_id : ""
  azure_client_secret_arn = var.enable_azure_oauth ? var.azure_client_secret_arn : ""

  # Google OAuth
  google_client_id         = var.enable_google_oauth ? var.google_oauth_client_id : ""
  google_client_secret_arn = var.enable_google_oauth ? var.google_oauth_secret_arn : ""

  # Email configuration (SES)
  smtp_from_email = "chat@${var.domain_name}"
  smtp_from_name  = "Zulip"
}

module "bookstack" {
  source = "../../../modules/aws/apps/bookstack"

  project         = var.project
  environment     = var.environment
  region          = var.region
  domain_name     = var.domain_name
  route53_zone_id = var.route53_zone_id

  # Network
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # ALB
  alb_dns_name          = module.alb.alb_dns_name
  alb_zone_id           = module.alb.alb_zone_id
  alb_listener_arn      = module.alb.https_listener_arn
  alb_security_group_id = module.alb.security_group_id

  # ECS
  ecs_cluster_id              = module.ecs.cluster_id
  ecs_tasks_security_group_id = module.ecs.tasks_security_group_id
  task_execution_role_arn     = module.ecs.task_execution_role_arn
  task_execution_role_name    = module.ecs.task_execution_role_name
  task_role_arn               = module.ecs.task_role_arn
  task_role_name              = module.ecs.task_role_name

  # Configuration sized for ~100 concurrent users (production-ready HA)
  db_instance_class      = "db.t3.small" # 2GB RAM, non-burstable under load
  db_multi_az            = true          # HA: automatic failover
  db_deletion_protection = false
  db_skip_final_snapshot = true
  ecs_cpu                = 1024          # ~1 vCPU
  ecs_memory             = 2048          # 2GB RAM
  desired_count          = 2             # HA: multiple instances

  # Azure AD OAuth (takes priority if configured)
  azure_tenant_id         = var.enable_azure_oauth ? var.azure_tenant_id : ""
  azure_client_id         = var.enable_azure_oauth ? var.azure_client_id : ""
  azure_client_secret_arn = var.enable_azure_oauth ? var.azure_client_secret_arn : ""

  # Google OAuth (used if Azure AD not configured)
  google_client_id         = var.enable_google_oauth ? var.google_oauth_client_id : ""
  google_client_secret_arn = var.enable_google_oauth ? var.google_oauth_secret_arn : ""

  # OIDC configuration (ABANDONED - kept for future reference)
  oidc_issuer            = var.enable_zitadel_oidc ? data.aws_ssm_parameter.oidc_issuer[0].value : ""
  oidc_client_id         = var.enable_zitadel_oidc ? data.aws_ssm_parameter.bookstack_oidc_client_id[0].value : ""
  oidc_client_secret_arn = var.enable_zitadel_oidc ? data.aws_ssm_parameter.bookstack_oidc_secret_arn[0].value : ""

  # Use ECR image to avoid Docker Hub rate limits
  container_image = "${module.ecr.repository_urls["bookstack"]}:latest"

  # Email notifications (SES)
  smtp_from_email = "docs@${var.domain_name}"
}

module "mattermost" {
  source = "../../../modules/aws/apps/mattermost"

  project         = var.project
  environment     = var.environment
  domain_name     = var.domain_name
  route53_zone_id = var.route53_zone_id

  # Use mm.dev subdomain to avoid conflict with Zulip (chat.dev)
  subdomain = "mm"

  # Network
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # ALB
  alb_dns_name          = module.alb.alb_dns_name
  alb_zone_id           = module.alb.alb_zone_id
  alb_listener_arn      = module.alb.https_listener_arn
  alb_security_group_id = module.alb.security_group_id

  # ECS
  ecs_cluster_id              = module.ecs.cluster_id
  ecs_tasks_security_group_id = module.ecs.tasks_security_group_id
  task_execution_role_arn     = module.ecs.task_execution_role_arn
  task_execution_role_name    = module.ecs.task_execution_role_name
  task_role_arn               = module.ecs.task_role_arn

  # Configuration sized for ~100 concurrent users (production-ready HA)
  db_instance_class      = "db.t3.small" # 2GB RAM, non-burstable under load
  db_multi_az            = true          # HA: automatic failover
  db_deletion_protection = false
  db_skip_final_snapshot = true
  ecs_cpu                = 1024          # ~1 vCPU
  ecs_memory             = 2048          # 2GB RAM
  desired_count          = 2             # HA: multiple instances

  # Allow open signup for dev
  enable_open_server = true

  # Azure AD (Office 365) OAuth
  azure_tenant_id         = var.enable_azure_oauth ? var.azure_tenant_id : ""
  azure_client_id         = var.enable_azure_oauth ? var.azure_client_id : ""
  azure_client_secret_arn = var.enable_azure_oauth ? var.azure_client_secret_arn : ""

  # OIDC configuration (reads from SSM - created by dev/oidc/)
  oidc_issuer            = var.enable_zitadel_oidc ? data.aws_ssm_parameter.oidc_issuer[0].value : ""
  oidc_client_id         = var.enable_zitadel_oidc ? data.aws_ssm_parameter.mattermost_oidc_client_id[0].value : ""
  oidc_client_secret_arn = var.enable_zitadel_oidc ? data.aws_ssm_parameter.mattermost_oidc_secret_arn[0].value : ""

  # Email configuration (SES)
  region          = var.region
  smtp_from_email = "mm@${var.domain_name}"

  # Use ECR image to avoid Docker Hub rate limits
  container_image = "${module.ecr.repository_urls["mattermost"]}:latest"
}

module "docusaurus" {
  source = "../../../modules/aws/apps/docusaurus"

  project         = var.project
  environment     = var.environment
  domain_name     = var.domain_name
  route53_zone_id = var.route53_zone_id

  # Network
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # ALB
  alb_dns_name          = module.alb.alb_dns_name
  alb_zone_id           = module.alb.alb_zone_id
  alb_listener_arn      = module.alb.https_listener_arn
  alb_security_group_id = module.alb.security_group_id

  # ECS
  ecs_cluster_id              = module.ecs.cluster_id
  ecs_tasks_security_group_id = module.ecs.tasks_security_group_id
  task_execution_role_arn     = module.ecs.task_execution_role_arn
  task_role_arn               = module.ecs.task_role_arn

  # Dev-specific configuration
  ecs_cpu    = 256
  ecs_memory = 512

  # ALB OIDC Authentication (uses Azure AD if configured, else Google OAuth)
  enable_alb_oidc_auth = var.enable_docusaurus_auth
  alb_oidc_config      = local.docusaurus_oidc_config
}

module "outline" {
  source = "../../../modules/aws/apps/outline"

  project         = var.project
  environment     = var.environment
  region          = var.region
  domain_name     = var.domain_name
  route53_zone_id = var.route53_zone_id

  # Network
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # ALB
  alb_dns_name          = module.alb.alb_dns_name
  alb_zone_id           = module.alb.alb_zone_id
  alb_listener_arn      = module.alb.https_listener_arn
  alb_security_group_id = module.alb.security_group_id

  # ECS
  ecs_cluster_id              = module.ecs.cluster_id
  ecs_tasks_security_group_id = module.ecs.tasks_security_group_id
  task_execution_role_arn     = module.ecs.task_execution_role_arn
  task_execution_role_name    = module.ecs.task_execution_role_name
  task_role_arn               = module.ecs.task_role_arn
  task_role_name              = module.ecs.task_role_name

  # Configuration sized for ~100 concurrent users (production-ready HA)
  db_instance_class      = "db.t3.small"   # 2GB RAM, non-burstable under load
  db_multi_az            = true            # HA: automatic failover
  db_deletion_protection = false
  db_skip_final_snapshot = true
  redis_node_type        = "cache.t3.small" # 1.5GB RAM for sessions/cache
  ecs_cpu                = 1024             # ~1 vCPU
  ecs_memory             = 2048             # 2GB RAM
  desired_count          = 2               # HA: multiple instances

  # Slack OAuth - works with ANY Slack workspace (free/personal)
  # This is the recommended auth method for personal accounts.
  # Create a Slack app at https://api.slack.com/apps and store credentials in Secrets Manager.
  slack_client_id         = var.outline_slack_client_id
  slack_client_secret_arn = var.outline_slack_secret_arn

  # SMTP for email notifications (NOT for authentication - Outline requires OAuth)
  enable_email_auth = true
  smtp_from_email   = "wiki@${var.domain_name}"

  # Note: Google/Azure OAuth require organizational accounts (not personal Gmail/Microsoft).
  # See gotchas.md "Outline Requires OAuth Provider"

  # Use ECR image to avoid Docker Hub rate limits
  container_image = "${module.ecr.repository_urls["outline"]}:latest"
}

# =============================================================================
# Governance - Cost management, lifecycle enforcement, and alerting
# =============================================================================

module "governance" {
  source = "../../../modules/aws/governance"

  project     = var.project
  environment = var.environment
  owner_email = var.owner_email

  monthly_budget_limit       = var.monthly_budget_limit
  lifecycle_warning_days     = 30
  lifecycle_termination_days = 60
  enable_auto_termination    = var.enable_auto_termination

  tags = {
    Component = "governance"
  }
}

# =============================================================================
# Mattermost <-> Outline Bridge
# Bi-directional integration: slash commands and webhooks
# =============================================================================

module "bridge" {
  count  = var.enable_mm_outline_bridge ? 1 : 0
  source = "../../../modules/aws/integrations/bridge"

  project         = var.project
  environment     = var.environment
  domain_name     = var.domain_name
  route53_zone_id = module.vpc.route53_zone_id

  # Outline configuration
  outline_api_key_secret_arn = var.outline_api_key_secret_arn
  outline_collection_id      = var.outline_default_collection_id
  outline_base_url           = "https://wiki.${var.environment}.${var.domain_name}"

  # Mattermost configuration
  mattermost_webhook_secret_arn = var.mattermost_webhook_secret_arn

  tags = {
    Component = "integrations"
  }
}
