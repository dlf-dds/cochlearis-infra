# Zitadel Identity Provider Module
#
# Self-hosted Zitadel for SSO authentication

locals {
  name_prefix = "${var.project}-${var.environment}"
  domain      = "auth.${var.environment}.${var.domain_name}"
}

# SSL Certificate (only created if not provided externally)
module "certificate" {
  count  = var.create_certificate ? 1 : 0
  source = "../../acm-certificate"

  project     = var.project
  environment = var.environment
  domain_name = local.domain
  zone_id     = var.route53_zone_id
}

# Route53 record
resource "aws_route53_record" "main" {
  zone_id = var.route53_zone_id
  name    = local.domain
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# PostgreSQL database
module "database" {
  source = "../../rds-postgres"

  project            = var.project
  environment        = var.environment
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids

  identifier    = "zitadel"
  database_name = "zitadel"

  allowed_security_group_ids = [var.ecs_tasks_security_group_id]

  instance_class      = var.db_instance_class
  allocated_storage   = var.db_allocated_storage
  multi_az            = var.db_multi_az
  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = var.db_skip_final_snapshot
}

# Master key secret
resource "random_password" "master_key" {
  length  = 32
  special = false
}

# Initial admin password
resource "random_password" "admin_password" {
  length  = 24
  special = true
}

resource "aws_secretsmanager_secret" "master_key" {
  name        = "${local.name_prefix}-zitadel-master-key"
  description = "Zitadel master key for encryption"

  tags = {
    Name = "${local.name_prefix}-zitadel-master-key"
  }
}

resource "aws_secretsmanager_secret_version" "master_key" {
  secret_id = aws_secretsmanager_secret.master_key.id
  secret_string = jsonencode({
    key            = random_password.master_key.result
    admin_password = random_password.admin_password.result
  })
}

# Note: ALB -> ECS security group rules are managed centrally in the ECS cluster module
# to avoid duplicate rule conflicts when multiple apps use the same ports.

# SES SMTP user for sending emails
module "ses_user" {
  source = "../../ses-smtp-user"

  name = "${local.name_prefix}-zitadel-ses"
  tags = {
    Name = "${local.name_prefix}-zitadel-ses"
  }
}

# IAM policy for secrets access
resource "aws_iam_role_policy" "secrets_access" {
  name = "${local.name_prefix}-zitadel-secrets-access"
  role = var.task_execution_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.master_key.arn,
          module.database.master_password_secret_arn,
          module.ses_user.smtp_credentials_secret_arn
        ]
      }
    ]
  })
}

# ECS Service
module "service" {
  source = "../../ecs-service"

  project     = var.project
  environment = var.environment

  service_name = "zitadel"
  cluster_id   = var.ecs_cluster_id
  vpc_id       = var.vpc_id

  private_subnet_ids = var.private_subnet_ids
  security_group_ids = [var.ecs_tasks_security_group_id]

  task_execution_role_arn = var.task_execution_role_arn
  task_role_arn           = var.task_role_arn

  container_image   = var.container_image
  container_port    = 8080
  container_command = ["start-from-init", "--masterkeyFromEnv", "--tlsMode", "external"]

  cpu           = var.ecs_cpu
  memory        = var.ecs_memory
  desired_count = var.desired_count

  environment_variables = merge(
    {
      ZITADEL_DATABASE_POSTGRES_HOST           = module.database.address
      ZITADEL_DATABASE_POSTGRES_PORT           = tostring(module.database.port)
      ZITADEL_DATABASE_POSTGRES_DATABASE       = module.database.database_name
      ZITADEL_DATABASE_POSTGRES_USER_USERNAME  = module.database.master_username
      ZITADEL_DATABASE_POSTGRES_USER_SSL_MODE  = "require"
      ZITADEL_DATABASE_POSTGRES_ADMIN_USERNAME = module.database.master_username
      ZITADEL_DATABASE_POSTGRES_ADMIN_SSL_MODE = "require"
      ZITADEL_EXTERNALSECURE                   = "true"
      ZITADEL_EXTERNALDOMAIN                   = local.domain
      ZITADEL_EXTERNALPORT                     = "443"
      ZITADEL_FIRSTINSTANCE_ORG_HUMAN_USERNAME = var.admin_username
      # Use legacy bundled Login UI (v4 split it into separate Next.js app)
      ZITADEL_DEFAULTINSTANCE_FEATURES_LOGINV2_REQUIRED = "false"
    },
    # SMTP configuration for email sending (SES)
    var.smtp_from_email != null ? {
      ZITADEL_DEFAULTINSTANCE_SMTPCONFIGURATION_SMTP_HOST = "email-smtp.${var.region}.amazonaws.com:587"
      ZITADEL_DEFAULTINSTANCE_SMTPCONFIGURATION_TLS       = "true"
      ZITADEL_DEFAULTINSTANCE_SMTPCONFIGURATION_FROM      = var.smtp_from_email
      ZITADEL_DEFAULTINSTANCE_SMTPCONFIGURATION_FROMNAME  = var.smtp_from_name
    } : {}
  )

  secrets = merge(
    {
      ZITADEL_DATABASE_POSTGRES_USER_PASSWORD  = "${module.database.master_password_secret_arn}:password::"
      ZITADEL_DATABASE_POSTGRES_ADMIN_PASSWORD = "${module.database.master_password_secret_arn}:password::"
      ZITADEL_MASTERKEY                        = "${aws_secretsmanager_secret.master_key.arn}:key::"
      ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORD = "${aws_secretsmanager_secret.master_key.arn}:admin_password::"
    },
    # SMTP credentials (SES)
    var.smtp_from_email != null ? {
      ZITADEL_DEFAULTINSTANCE_SMTPCONFIGURATION_SMTP_USER     = "${module.ses_user.smtp_credentials_secret_arn}:username::"
      ZITADEL_DEFAULTINSTANCE_SMTPCONFIGURATION_SMTP_PASSWORD = "${module.ses_user.smtp_credentials_secret_arn}:password::"
    } : {}
  )

  # ALB Integration
  create_alb_target_group       = true
  alb_listener_arn              = var.alb_listener_arn
  host_header                   = local.domain
  listener_rule_priority        = var.listener_rule_priority
  health_check_path             = "/debug/healthz"
  health_check_matcher          = "200"
  target_group_protocol_version = "HTTP2" # Required for gRPC/Terraform provider
}
