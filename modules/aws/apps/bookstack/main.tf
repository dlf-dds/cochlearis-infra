# BookStack Documentation Platform Module
#
# Self-hosted BookStack wiki with SSO support

locals {
  name_prefix    = "${var.project}-${var.environment}"
  domain         = "docs.${var.environment}.${var.domain_name}"
  oidc_enabled   = var.oidc_client_id != "" && var.oidc_client_secret_arn != ""
  google_enabled = var.google_client_id != "" && var.google_client_secret_arn != ""
  azure_enabled  = var.azure_client_id != "" && var.azure_client_secret_arn != "" && var.azure_tenant_id != ""
  smtp_enabled   = var.smtp_from_email != ""
}

# SSL Certificate
module "certificate" {
  source = "../../acm-certificate"

  project     = var.project
  environment = var.environment
  domain_name = local.domain
  zone_id     = var.route53_zone_id
}

# Add certificate to ALB
resource "aws_lb_listener_certificate" "main" {
  listener_arn    = var.alb_listener_arn
  certificate_arn = module.certificate.validation_certificate_arn
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

# MySQL database (BookStack only supports MySQL/MariaDB)
module "database" {
  source = "../../rds-mysql"

  project            = var.project
  environment        = var.environment
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids

  identifier    = "bookstack"
  database_name = "bookstack"

  allowed_security_group_ids = [var.ecs_tasks_security_group_id]

  instance_class      = var.db_instance_class
  allocated_storage   = var.db_allocated_storage
  multi_az            = var.db_multi_az
  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = var.db_skip_final_snapshot
}

# SES SMTP user for email notifications
module "ses_user" {
  count  = local.smtp_enabled ? 1 : 0
  source = "../../ses-smtp-user"

  name = "${local.name_prefix}-bookstack-ses"
  tags = {
    Name = "${local.name_prefix}-bookstack-ses"
  }
}

# Application key secret
resource "random_password" "app_key" {
  length  = 32
  special = false
}

# Random suffix to avoid Secrets Manager name collision on recreate
resource "random_id" "secret_suffix" {
  byte_length = 4
}

resource "aws_secretsmanager_secret" "app_key" {
  name        = "${local.name_prefix}-bookstack-app-key-${random_id.secret_suffix.hex}"
  description = "BookStack Laravel application key"

  tags = {
    Name = "${local.name_prefix}-bookstack-app-key"
  }
}

resource "aws_secretsmanager_secret_version" "app_key" {
  secret_id     = aws_secretsmanager_secret.app_key.id
  secret_string = "base64:${base64encode(random_password.app_key.result)}"
}

# S3 bucket for uploads
resource "aws_s3_bucket" "uploads" {
  bucket = "${local.name_prefix}-bookstack-uploads"

  tags = {
    Name = "${local.name_prefix}-bookstack-uploads"
  }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# IAM policy for S3 access
resource "aws_iam_role_policy" "s3_access" {
  name = "${local.name_prefix}-bookstack-s3-access"
  role = var.task_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.uploads.arn,
          "${aws_s3_bucket.uploads.arn}/*"
        ]
      }
    ]
  })
}

# Note: ALB -> ECS security group rules are managed centrally in the ECS cluster module
# to avoid duplicate rule conflicts when multiple apps use the same ports.

# IAM policy for secrets access
resource "aws_iam_role_policy" "secrets_access" {
  name = "${local.name_prefix}-bookstack-secrets-access"
  role = var.task_execution_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = concat(
          [
            aws_secretsmanager_secret.app_key.arn,
            module.database.master_password_secret_arn
          ],
          local.oidc_enabled ? [var.oidc_client_secret_arn] : [],
          local.google_enabled ? [var.google_client_secret_arn] : [],
          local.azure_enabled ? [var.azure_client_secret_arn] : [],
          local.smtp_enabled ? [module.ses_user[0].smtp_credentials_secret_arn] : []
        )
      }
    ]
  })
}

# ECS Service
module "service" {
  source = "../../ecs-service"

  project     = var.project
  environment = var.environment

  service_name = "bookstack"
  cluster_id   = var.ecs_cluster_id
  vpc_id       = var.vpc_id

  private_subnet_ids = var.private_subnet_ids
  security_group_ids = [var.ecs_tasks_security_group_id]

  task_execution_role_arn = var.task_execution_role_arn
  task_role_arn           = var.task_role_arn

  container_image = var.container_image
  container_port  = 80

  cpu           = var.ecs_cpu
  memory        = var.ecs_memory
  desired_count = var.desired_count

  environment_variables = merge(
    {
      # App settings
      APP_URL = "https://${local.domain}"
      APP_ENV = "production"

      # Trust all proxies (required for ALB SSL termination)
      # Without this, Laravel generates HTTP callback URLs instead of HTTPS
      APP_PROXIES = "*"

      # Database (MySQL)
      DB_CONNECTION = "mysql"
      DB_HOST       = module.database.address
      DB_PORT       = tostring(module.database.port)
      DB_DATABASE   = module.database.database_name
      DB_USERNAME   = module.database.master_username

      # Session and cache
      SESSION_DRIVER        = "database"
      CACHE_DRIVER          = "database"
      SESSION_SECURE_COOKIE = "true"

      # File storage
      STORAGE_TYPE = "local"

      # Mail settings (SES) - only enable if smtp_from_email is set
      MAIL_DRIVER     = local.smtp_enabled ? "smtp" : "log"
      MAIL_HOST       = local.smtp_enabled ? module.ses_user[0].smtp_endpoint : ""
      MAIL_PORT       = "587"
      MAIL_FROM       = var.smtp_from_email != "" ? var.smtp_from_email : "noreply@${var.domain_name}"
      MAIL_FROM_NAME  = "BookStack"
      MAIL_ENCRYPTION = "tls"
    },
    # Authentication - BookStack supports multiple social providers simultaneously
    {
      AUTH_METHOD = "standard" # BookStack uses standard + social providers
    },
    # Azure AD OAuth (when enabled)
    local.azure_enabled ? {
      AZURE_APP_ID        = var.azure_client_id
      AZURE_TENANT        = var.azure_tenant_id
      AZURE_AUTO_REGISTER = "true" # Auto-create accounts for Azure AD users
      AZURE_AUTO_CONFIRM  = "true" # Skip email confirmation for Azure AD users
    } : {},
    # Google OAuth (when enabled - independent of Azure AD)
    local.google_enabled ? {
      GOOGLE_APP_ID        = var.google_client_id
      GOOGLE_AUTO_REGISTER = "true" # Auto-create accounts for new Google users
      GOOGLE_AUTO_CONFIRM  = "true" # Skip email confirmation for Google users
    } : {}
  )

  secrets = merge(
    {
      DB_PASSWORD = "${module.database.master_password_secret_arn}:password::"
      APP_KEY     = aws_secretsmanager_secret.app_key.arn
    },
    # Azure AD secret (when enabled)
    local.azure_enabled ? {
      AZURE_APP_SECRET = "${var.azure_client_secret_arn}:client_secret::"
    } : {},
    # Google secret (when enabled - independent of Azure AD)
    local.google_enabled ? {
      GOOGLE_APP_SECRET = "${var.google_client_secret_arn}:client_secret::"
    } : {},
    # SMTP credentials (when enabled)
    local.smtp_enabled ? {
      MAIL_USERNAME = "${module.ses_user[0].smtp_credentials_secret_arn}:username::"
      MAIL_PASSWORD = "${module.ses_user[0].smtp_credentials_secret_arn}:password::"
    } : {}
  )

  # ALB Integration
  create_alb_target_group = true
  alb_listener_arn        = var.alb_listener_arn
  host_header             = local.domain
  listener_rule_priority  = var.listener_rule_priority
  health_check_path       = "/status"
  health_check_matcher    = "200"
}
