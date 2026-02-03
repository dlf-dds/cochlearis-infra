# Zulip Mini - Simplified All-in-One Deployment
#
# Uses docker-zulip's internal PostgreSQL and Redis for simplicity.
# No sidecars, no external ElastiCache - just works.
#
# This is the "nuclear option" to get Zulip running quickly.

locals {
  name_prefix    = "${var.project}-${var.environment}"
  domain         = "chatmini.${var.environment}.${var.domain_name}"
  google_enabled = var.google_client_id != "" && var.google_client_secret_arn != ""
  azure_enabled  = var.azure_client_id != "" && var.azure_client_secret_arn != "" && var.azure_tenant_id != ""
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

# Random suffix to avoid Secrets Manager name collision on recreate
resource "random_id" "secret_suffix" {
  byte_length = 4
}

# Secret key for Django
resource "random_password" "secret_key" {
  length  = 64
  special = false
}

# PostgreSQL password (required by docker-zulip even for internal PostgreSQL)
resource "random_password" "postgres_password" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "secrets" {
  name        = "${local.name_prefix}-zulip-mini-secrets-${random_id.secret_suffix.hex}"
  description = "Zulip Mini application secrets"

  tags = {
    Name = "${local.name_prefix}-zulip-mini-secrets"
  }
}

resource "aws_secretsmanager_secret_version" "secrets" {
  secret_id = aws_secretsmanager_secret.secrets.id
  secret_string = jsonencode({
    secret_key        = random_password.secret_key.result
    postgres_password = random_password.postgres_password.result
  })
}

# EFS for persistent storage - uses uid 1000 (zulip user)
module "efs" {
  source = "../../efs"

  project     = var.project
  environment = var.environment
  name        = "zulip-mini"

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  allowed_security_group_ids = [var.ecs_tasks_security_group_id]

  # Zulip runs as user 1000 (zulip)
  posix_user_uid             = 1000
  posix_user_gid             = 1000
  root_directory_path        = "/zulip-mini"
  root_directory_permissions = "755"
}

# IAM policy for secrets access
resource "aws_iam_role_policy" "secrets_access" {
  name = "${local.name_prefix}-zulip-mini-secrets-access"
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
          [aws_secretsmanager_secret.secrets.arn],
          local.google_enabled ? [var.google_client_secret_arn] : [],
          local.azure_enabled ? [var.azure_client_secret_arn] : []
        )
      }
    ]
  })
}

# IAM policy for EFS access
resource "aws_iam_role_policy" "efs_access" {
  name = "${local.name_prefix}-zulip-mini-efs-access"
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
            "elasticfilesystem:AccessPointArn" = module.efs.access_point_arn
          }
        }
      }
    ]
  })
}

# ECS Service - Single container, all-in-one
module "service" {
  source = "../../ecs-service"

  project     = var.project
  environment = var.environment

  service_name = "zulip-mini"
  cluster_id   = var.ecs_cluster_id
  vpc_id       = var.vpc_id

  private_subnet_ids = var.private_subnet_ids
  security_group_ids = [var.ecs_tasks_security_group_id]

  task_execution_role_arn = var.task_execution_role_arn
  task_role_arn           = var.task_role_arn

  container_image = var.container_image
  container_port  = 80

  # Zulip needs decent resources for all-in-one (includes Postgres + Redis + Django)
  cpu           = var.ecs_cpu
  memory        = var.ecs_memory
  desired_count = var.desired_count

  environment_variables = merge(
    {
      # Core Zulip settings
      SETTING_EXTERNAL_HOST       = local.domain
      SETTING_ZULIP_ADMINISTRATOR = var.admin_email
      DISABLE_HTTPS               = "True"
      SSL_CERTIFICATE_GENERATION  = "self-signed"
      LOADBALANCER_IPS            = var.vpc_cidr

      # Use internal PostgreSQL (docker-zulip manages it)
      # DB_HOST defaults to localhost inside the container

      # Use internal Redis (docker-zulip manages it)
      # REDIS_HOST defaults to localhost inside the container

      # Disable S3 - use local storage for simplicity
      # Data will persist on EFS

      # Allow organization creation without a link (dev environment)
      SETTING_OPEN_REALM_CREATION = "True"

      # Disable email for now - we can add it later once working
      SETTING_EMAIL_HOST = ""
    },
    # Authentication backends
    local.azure_enabled && local.google_enabled ? {
      SETTING_AUTHENTICATION_BACKENDS        = "(\"zproject.backends.AzureADAuthBackend\", \"zproject.backends.GoogleAuthBackend\", \"zproject.backends.EmailAuthBackend\")"
      SETTING_SOCIAL_AUTH_AZUREAD_OAUTH2_KEY = var.azure_client_id
      SETTING_SOCIAL_AUTH_GOOGLE_OAUTH2_KEY  = var.google_client_id
    } : local.azure_enabled ? {
      SETTING_AUTHENTICATION_BACKENDS        = "(\"zproject.backends.AzureADAuthBackend\", \"zproject.backends.EmailAuthBackend\")"
      SETTING_SOCIAL_AUTH_AZUREAD_OAUTH2_KEY = var.azure_client_id
    } : local.google_enabled ? {
      SETTING_AUTHENTICATION_BACKENDS       = "(\"zproject.backends.GoogleAuthBackend\", \"zproject.backends.EmailAuthBackend\")"
      SETTING_SOCIAL_AUTH_GOOGLE_OAUTH2_KEY = var.google_client_id
    } : {
      SETTING_AUTHENTICATION_BACKENDS = "(\"zproject.backends.EmailAuthBackend\",)"
    }
  )

  secrets = merge(
    {
      SECRETS_secret_key        = "${aws_secretsmanager_secret.secrets.arn}:secret_key::"
      SECRETS_postgres_password = "${aws_secretsmanager_secret.secrets.arn}:postgres_password::"
    },
    local.azure_enabled ? {
      SECRETS_social_auth_azuread_oauth2_secret = "${var.azure_client_secret_arn}:client_secret::"
    } : {},
    local.google_enabled ? {
      SECRETS_social_auth_google_oauth2_secret = "${var.google_client_secret_arn}:client_secret::"
    } : {}
  )

  # ALB Integration
  create_alb_target_group = true
  alb_listener_arn        = var.alb_listener_arn
  host_header             = local.domain
  listener_rule_priority  = var.listener_rule_priority
  health_check_path       = "/"
  health_check_matcher    = "200-399,400"

  # EFS volume for all data (Postgres data, uploads, etc.)
  efs_volumes = [
    {
      name            = "zulip-data"
      file_system_id  = module.efs.file_system_id
      access_point_id = module.efs.access_point_id
      container_path  = "/data"
      read_only       = false
    }
  ]
}
