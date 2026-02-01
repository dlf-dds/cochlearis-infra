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
  alb_ingress_ports     = [80, 8065, 8080] # 80 for Zulip/BookStack/Docusaurus, 8065 for Mattermost, 8080 for Zitadel
}

# Primary SSL certificate (for ALB default - using auth domain)
module "primary_certificate" {
  source = "../../../modules/aws/acm-certificate"

  project     = var.project
  environment = var.environment
  domain_name = "auth.${var.environment}.${var.domain_name}"
  zone_id     = var.route53_zone_id
}

# Shared ALB for all services
module "alb" {
  source = "../../../modules/aws/alb"

  project           = var.project
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  certificate_arn   = module.primary_certificate.validation_certificate_arn
}

# =============================================================================
# Private DNS Zone for Internal Service-to-Service Communication
# =============================================================================
# Resolves service domains to ALB within the VPC, avoiding hairpin NAT issues
# where ECS tasks would otherwise need to go out to internet and back in.

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

# Internal DNS records pointing to ALB (split-horizon DNS)
resource "aws_route53_record" "auth_private" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "auth.${var.environment}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "docs_private" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "docs.${var.environment}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "chat_private" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "chat.${var.environment}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "mm_private" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "mm.${var.environment}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
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
}

# =============================================================================
# Zitadel OIDC Applications (enabled after bootstrap script creates service account)
# =============================================================================

# Read organization ID from SSM (created by bootstrap script)
data "aws_ssm_parameter" "zitadel_org_id" {
  count = var.enable_zitadel_oidc ? 1 : 0
  name  = "/${var.project}/${var.environment}/zitadel/organization-id"
}

module "zitadel_oidc" {
  source = "../../../modules/aws/zitadel-oidc"
  count  = var.enable_zitadel_oidc ? 1 : 0

  organization_id    = data.aws_ssm_parameter.zitadel_org_id[0].value
  project_name       = "Cochlearis"
  secret_prefix      = "${var.project}-${var.environment}"
  bookstack_domain   = "docs.${var.environment}.${var.domain_name}"
  zulip_domain       = "chat.${var.environment}.${var.domain_name}"
  mattermost_domain  = "mm.${var.environment}.${var.domain_name}"

  depends_on = [module.zitadel]
}

module "zulip" {
  source = "../../../modules/aws/apps/zulip"

  project         = var.project
  environment     = var.environment
  region          = var.region
  domain_name     = var.domain_name
  route53_zone_id = var.route53_zone_id

  # Network
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = "10.0.0.0/16"
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

  # Dev-specific configuration (PostgreSQL runs as sidecar, higher resources needed)
  redis_node_type = "cache.t3.micro"
  ecs_cpu         = 2048 # Zulip + PostgreSQL sidecar
  ecs_memory      = 4096 # Zulip + PostgreSQL sidecar
  admin_email     = var.owner_email

  # OIDC configuration (enabled after running bootstrap script)
  oidc_issuer            = var.enable_zitadel_oidc ? module.zitadel.url : ""
  oidc_client_id         = var.enable_zitadel_oidc ? module.zitadel_oidc[0].zulip_client_id : ""
  oidc_client_secret_arn = var.enable_zitadel_oidc ? module.zitadel_oidc[0].zulip_oidc_secret_arn : ""
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

  # Dev-specific configuration
  db_instance_class      = "db.t3.micro"
  db_multi_az            = false
  db_deletion_protection = false
  db_skip_final_snapshot = true
  ecs_cpu                = 512
  ecs_memory             = 1024

  # OIDC configuration (enabled after running bootstrap script)
  oidc_issuer            = var.enable_zitadel_oidc ? module.zitadel.url : ""
  oidc_client_id         = var.enable_zitadel_oidc ? module.zitadel_oidc[0].bookstack_client_id : ""
  oidc_client_secret_arn = var.enable_zitadel_oidc ? module.zitadel_oidc[0].bookstack_oidc_secret_arn : ""
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

  # Dev-specific configuration
  db_instance_class      = "db.t3.micro"
  db_multi_az            = false
  db_deletion_protection = false
  db_skip_final_snapshot = true
  ecs_cpu                = 512
  ecs_memory             = 1024

  # Allow open signup for dev
  enable_open_server = true

  # OIDC configuration (enabled after running bootstrap script)
  oidc_issuer            = var.enable_zitadel_oidc ? module.zitadel.url : ""
  oidc_client_id         = var.enable_zitadel_oidc ? module.zitadel_oidc[0].mattermost_client_id : ""
  oidc_client_secret_arn = var.enable_zitadel_oidc ? module.zitadel_oidc[0].mattermost_oidc_secret_arn : ""
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
