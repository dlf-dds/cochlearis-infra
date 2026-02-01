# Outline Wiki Module
#
# Self-hosted Outline wiki with SSO support

locals {
  name_prefix  = "${var.project}-${var.environment}"
  domain       = "wiki.${var.environment}.${var.domain_name}"
  oidc_enabled = var.oidc_client_id != "" && var.oidc_client_secret_arn != ""
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

# PostgreSQL database
module "database" {
  source = "../../rds-postgres"

  project            = var.project
  environment        = var.environment
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids

  identifier    = "outline"
  database_name = "outline"

  allowed_security_group_ids = [var.ecs_tasks_security_group_id]

  instance_class      = var.db_instance_class
  allocated_storage   = var.db_allocated_storage
  multi_az            = var.db_multi_az
  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = var.db_skip_final_snapshot
}

# Redis for caching/sessions
module "redis" {
  source = "../../elasticache-redis"

  project     = var.project
  environment = var.environment
  vpc_id      = var.vpc_id

  identifier         = "outline"
  private_subnet_ids = var.private_subnet_ids

  allowed_security_group_ids = [var.ecs_tasks_security_group_id]

  node_type = var.redis_node_type
}

# Secret key for sessions
resource "random_password" "secret_key" {
  length  = 64
  special = false
}

resource "random_password" "utils_secret" {
  length  = 64
  special = false
}

# Random suffix to avoid Secrets Manager name collision on recreate
resource "random_id" "secret_suffix" {
  byte_length = 4
}

resource "aws_secretsmanager_secret" "app_secrets" {
  name        = "${local.name_prefix}-outline-secrets-${random_id.secret_suffix.hex}"
  description = "Outline application secrets"

  tags = {
    Name = "${local.name_prefix}-outline-secrets"
  }
}

resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    secret_key   = random_password.secret_key.result
    utils_secret = random_password.utils_secret.result
    # Full DATABASE_URL (Outline requires complete connection string)
    database_url = "postgres://${module.database.master_username}:${urlencode(module.database.master_password)}@${module.database.address}:${module.database.port}/${module.database.database_name}?sslmode=require"
  })
}

# S3 bucket for uploads
resource "aws_s3_bucket" "uploads" {
  bucket = "${local.name_prefix}-outline-uploads"

  tags = {
    Name = "${local.name_prefix}-outline-uploads"
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

resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE"]
    allowed_origins = ["https://${local.domain}"]
    max_age_seconds = 3000
  }
}

# IAM policy for S3 access
resource "aws_iam_role_policy" "s3_access" {
  name = "${local.name_prefix}-outline-s3-access"
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
          "s3:ListBucket",
          "s3:GetObjectAcl",
          "s3:PutObjectAcl"
        ]
        Resource = [
          aws_s3_bucket.uploads.arn,
          "${aws_s3_bucket.uploads.arn}/*"
        ]
      }
    ]
  })
}

# IAM policy for secrets access
resource "aws_iam_role_policy" "secrets_access" {
  name = "${local.name_prefix}-outline-secrets-access"
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
          [aws_secretsmanager_secret.app_secrets.arn],
          local.oidc_enabled ? [var.oidc_client_secret_arn] : []
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

  service_name = "outline"
  cluster_id   = var.ecs_cluster_id
  vpc_id       = var.vpc_id

  private_subnet_ids = var.private_subnet_ids
  security_group_ids = [var.ecs_tasks_security_group_id]

  task_execution_role_arn = var.task_execution_role_arn
  task_role_arn           = var.task_role_arn

  container_image = var.container_image
  container_port  = 3000

  cpu           = var.ecs_cpu
  memory        = var.ecs_memory
  desired_count = var.desired_count

  environment_variables = merge(
    {
      # App settings
      URL              = "https://${local.domain}"
      PORT             = "3000"
      FORCE_HTTPS      = "false" # ALB handles TLS
      ENABLE_UPDATES   = "false"
      WEB_CONCURRENCY  = "1"
      LOG_LEVEL        = "info"
      DEFAULT_LANGUAGE = "en_US"

      # Redis
      REDIS_URL = "redis://${module.redis.endpoint}:${module.redis.port}"

      # S3 Storage
      FILE_STORAGE              = "s3"
      AWS_S3_UPLOAD_BUCKET_NAME = aws_s3_bucket.uploads.id
      AWS_S3_UPLOAD_BUCKET_URL  = "https://${aws_s3_bucket.uploads.bucket_regional_domain_name}"
      AWS_S3_FORCE_PATH_STYLE   = "false"
      AWS_S3_ACL                = "private"
      AWS_REGION                = var.region
    },
    # OIDC SSO via Zitadel (only if configured)
    local.oidc_enabled ? {
      OIDC_CLIENT_ID    = var.oidc_client_id
      OIDC_AUTH_URI     = "${var.oidc_issuer != "" ? var.oidc_issuer : "https://auth.${var.environment}.${var.domain_name}"}/oauth/v2/authorize"
      OIDC_TOKEN_URI    = "${var.oidc_issuer != "" ? var.oidc_issuer : "https://auth.${var.environment}.${var.domain_name}"}/oauth/v2/token"
      OIDC_USERINFO_URI = "${var.oidc_issuer != "" ? var.oidc_issuer : "https://auth.${var.environment}.${var.domain_name}"}/oidc/v1/userinfo"
      OIDC_LOGOUT_URI   = "${var.oidc_issuer != "" ? var.oidc_issuer : "https://auth.${var.environment}.${var.domain_name}"}/oidc/v1/end_session"
      OIDC_DISPLAY_NAME = "Zitadel"
      OIDC_SCOPES       = "openid profile email"
    } : {}
  )

  secrets = merge(
    {
      SECRET_KEY   = "${aws_secretsmanager_secret.app_secrets.arn}:secret_key::"
      UTILS_SECRET = "${aws_secretsmanager_secret.app_secrets.arn}:utils_secret::"
      DATABASE_URL = "${aws_secretsmanager_secret.app_secrets.arn}:database_url::"
    },
    local.oidc_enabled ? {
      OIDC_CLIENT_SECRET = "${var.oidc_client_secret_arn}:client_secret::"
    } : {}
  )

  # ALB Integration
  create_alb_target_group = true
  alb_listener_arn        = var.alb_listener_arn
  host_header             = local.domain
  listener_rule_priority  = var.listener_rule_priority
  health_check_path       = "/_health"
  health_check_matcher    = "200"
}
