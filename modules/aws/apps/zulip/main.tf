# Zulip Chat Service Module
#
# Self-hosted Zulip with SSO support

locals {
  name_prefix  = "${var.project}-${var.environment}"
  domain       = "chat.${var.environment}.${var.domain_name}"
  oidc_enabled = var.oidc_client_id != "" && var.oidc_client_secret_arn != ""
  oidc_issuer  = var.oidc_issuer != "" ? var.oidc_issuer : "https://auth.${var.environment}.${var.domain_name}"
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

# PostgreSQL credentials (for sidecar container)
resource "random_password" "postgres_password" {
  length  = 32
  special = false
}

# Random suffix to avoid Secrets Manager name collision on recreate
resource "random_id" "secret_suffix" {
  byte_length = 4
}

resource "aws_secretsmanager_secret" "postgres" {
  name        = "${local.name_prefix}-zulip-postgres-${random_id.secret_suffix.hex}"
  description = "Zulip PostgreSQL password"

  tags = {
    Name = "${local.name_prefix}-zulip-postgres"
  }
}

resource "aws_secretsmanager_secret_version" "postgres" {
  secret_id = aws_secretsmanager_secret.postgres.id
  secret_string = jsonencode({
    password = random_password.postgres_password.result
  })
}

# Redis cache
module "redis" {
  source = "../../elasticache-redis"

  project            = var.project
  environment        = var.environment
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids

  identifier = "zulip"

  allowed_security_group_ids = [var.ecs_tasks_security_group_id]

  node_type = var.redis_node_type
}

# EFS for persistent storage (certificates, uploads, etc.)
module "efs" {
  source = "../../efs"

  project     = var.project
  environment = var.environment
  name        = "zulip"

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  allowed_security_group_ids = [var.ecs_tasks_security_group_id]

  # Zulip container runs as root (uid 0) but writes to /data
  posix_user_uid             = 0
  posix_user_gid             = 0
  root_directory_path        = "/zulip"
  root_directory_permissions = "755"
}

# EFS access point for PostgreSQL data (uid/gid 999 is postgres user in alpine)
resource "aws_efs_access_point" "postgres" {
  file_system_id = module.efs.file_system_id

  posix_user {
    gid = 999
    uid = 999
  }

  root_directory {
    path = "/postgres"

    creation_info {
      owner_gid   = 999
      owner_uid   = 999
      permissions = "700"
    }
  }

  tags = {
    Name = "${local.name_prefix}-zulip-postgres-ap"
  }
}

# S3 bucket for uploads
resource "aws_s3_bucket" "uploads" {
  bucket = "${local.name_prefix}-zulip-uploads"

  tags = {
    Name = "${local.name_prefix}-zulip-uploads"
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

# SES SMTP user
module "ses_user" {
  source = "../../ses-smtp-user"

  name = "${local.name_prefix}-zulip-ses"
  tags = {
    Name = "${local.name_prefix}-zulip-ses"
  }
}

# Application secrets
resource "random_password" "secret_key" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "secrets" {
  name        = "${local.name_prefix}-zulip-secrets-${random_id.secret_suffix.hex}"
  description = "Zulip application secrets"

  tags = {
    Name = "${local.name_prefix}-zulip-secrets"
  }
}

resource "aws_secretsmanager_secret_version" "secrets" {
  secret_id = aws_secretsmanager_secret.secrets.id
  secret_string = jsonencode({
    secret_key = random_password.secret_key.result
  })
}

# IAM policy for S3 access
resource "aws_iam_role_policy" "s3_access" {
  name = "${local.name_prefix}-zulip-s3-access"
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
  name = "${local.name_prefix}-zulip-secrets-access"
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
            aws_secretsmanager_secret.secrets.arn,
            aws_secretsmanager_secret.postgres.arn
          ],
          local.oidc_enabled ? [var.oidc_client_secret_arn] : []
        )
      }
    ]
  })
}

# IAM policy for EFS access
resource "aws_iam_role_policy" "efs_access" {
  name = "${local.name_prefix}-zulip-efs-access"
  role = var.task_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = module.efs.file_system_arn
        Condition = {
          StringEquals = {
            "elasticfilesystem:AccessPointArn" = [
              module.efs.access_point_arn,
              aws_efs_access_point.postgres.arn
            ]
          }
        }
      }
    ]
  })
}

# ECS Service
module "service" {
  source = "../../ecs-service"

  project     = var.project
  environment = var.environment

  service_name = "zulip"
  cluster_id   = var.ecs_cluster_id
  vpc_id       = var.vpc_id

  private_subnet_ids = var.private_subnet_ids
  security_group_ids = [var.ecs_tasks_security_group_id]

  task_execution_role_arn = var.task_execution_role_arn
  task_role_arn           = var.task_role_arn

  container_image = var.container_image
  container_port  = 80

  # Increased resources to accommodate PostgreSQL sidecar
  cpu           = var.ecs_cpu
  memory        = var.ecs_memory
  desired_count = var.desired_count

  environment_variables = merge(
    {
      # Zulip settings
      SETTING_EXTERNAL_HOST       = local.domain
      SETTING_ZULIP_ADMINISTRATOR = var.admin_email
      DISABLE_HTTPS               = "True"
      SSL_CERTIFICATE_GENERATION  = "self-signed"
      LOADBALANCER_IPS            = var.vpc_cidr

      # Database - Local PostgreSQL sidecar (localhost within task)
      # DB_HOST/DB_HOST_PORT/DB_USER are used by docker-zulip entrypoint for pg_isready check
      DB_HOST      = "127.0.0.1"
      DB_HOST_PORT = "5432"
      DB_USER      = "zulip"
      # No SSL needed for localhost connection
      PGSSLMODE = "disable"

      # Redis
      SETTING_REDIS_HOST = module.redis.endpoint
      SETTING_REDIS_PORT = tostring(module.redis.port)

      # S3 storage
      SETTING_LOCAL_UPLOADS_DIR      = ""
      SETTING_S3_AUTH_UPLOADS_BUCKET = aws_s3_bucket.uploads.id
      SETTING_S3_REGION              = var.region

      # Email (SES)
      SETTING_EMAIL_HOST            = "email-smtp.${var.region}.amazonaws.com"
      SETTING_EMAIL_HOST_USER       = module.ses_user.name
      SETTING_EMAIL_PORT            = "587"
      SETTING_EMAIL_USE_TLS         = "True"
      SETTING_NOREPLY_EMAIL_ADDRESS = "noreply@${var.domain_name}"

      # Allow organization creation without a link (dev environment)
      SETTING_OPEN_REALM_CREATION = "True"
    },
    # Authentication - OIDC via Zitadel (if configured) or standard
    local.oidc_enabled ? {
      # OIDC backend enabled
      SETTING_AUTHENTICATION_BACKENDS = "(\"zproject.backends.GenericOpenIdConnectBackend\",)"
      # SOCIAL_AUTH_OIDC_ENABLED_IDPS is a Python dict - must be valid Python syntax
      SETTING_SOCIAL_AUTH_OIDC_ENABLED_IDPS = "{\"zitadel\": {\"oidc_url\": \"${local.oidc_issuer}\", \"display_name\": \"Zitadel\", \"client_id\": \"${var.oidc_client_id}\", \"auto_signup\": True}}"
      SETTING_SOCIAL_AUTH_OIDC_FULL_NAME_VALIDATED = "True"
    } : {
      # Standard email/password auth when OIDC not configured
      SETTING_AUTHENTICATION_BACKENDS = "(\"zproject.backends.EmailAuthBackend\",)"
    }
  )

  secrets = merge(
    {
      SECRETS_postgres_password = "${aws_secretsmanager_secret.postgres.arn}:password::"
      SECRETS_secret_key        = "${aws_secretsmanager_secret.secrets.arn}:secret_key::"
    },
    local.oidc_enabled ? {
      SECRETS_social_auth_oidc_secret = "${var.oidc_client_secret_arn}:client_secret::"
    } : {}
  )

  # ALB Integration
  create_alb_target_group = true
  alb_listener_arn        = var.alb_listener_arn
  host_header             = local.domain
  listener_rule_priority  = var.listener_rule_priority
  # Health check uses 400 matcher because ALB sends requests without Host header,
  # which nginx rejects with 400. Container is healthy if it responds at all.
  health_check_path       = "/"
  health_check_matcher    = "200-399,400"

  # EFS volumes for persistent storage
  efs_volumes = [
    {
      name            = "zulip-data"
      file_system_id  = module.efs.file_system_id
      access_point_id = module.efs.access_point_id
      container_path  = "/data"
      read_only       = false
    },
    {
      name            = "postgres-data"
      file_system_id  = module.efs.file_system_id
      access_point_id = aws_efs_access_point.postgres.id
      container_path  = "/var/lib/postgresql/data"
      read_only       = false
    }
  ]

  # PostgreSQL sidecar container (using Zulip's PostgreSQL image with hunspell dictionaries)
  # Data persisted via EFS - survives task restarts
  sidecar_containers = [
    {
      name      = "postgres"
      image     = "zulip/zulip-postgresql:14"
      essential = true
      port      = 5432
      user      = "999:999" # Run as postgres user to avoid chown issues with EFS
      environment_variables = {
        POSTGRES_USER = "zulip"
        POSTGRES_DB   = "zulip"
        PGDATA        = "/var/lib/postgresql/data/pgdata"
      }
      secrets = {
        POSTGRES_PASSWORD = "${aws_secretsmanager_secret.postgres.arn}:password::"
      }
      health_check = {
        command      = ["CMD-SHELL", "pg_isready -U zulip -d zulip"]
        interval     = 10
        timeout      = 5
        retries      = 5
        start_period = 30
      }
      mount_points = [
        {
          volume_name    = "postgres-data"
          container_path = "/var/lib/postgresql/data"
          read_only      = false
        }
      ]
    }
  ]
}
