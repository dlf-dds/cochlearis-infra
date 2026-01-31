# Zulip Chat Service Deployment
#
# Self-hosted Zulip with SSO via Zitadel

locals {
  zulip_domain = "chat.dev.${var.domain_name}"
}

# SSL Certificate for Zulip
module "zulip_certificate" {
  source = "../../../modules/aws/acm-certificate"

  project     = var.project
  environment = var.environment
  domain_name = local.zulip_domain
  zone_id     = var.route53_zone_id
}

# Add Zulip certificate to ALB
resource "aws_lb_listener_certificate" "zulip" {
  listener_arn    = module.alb.https_listener_arn
  certificate_arn = module.zulip_certificate.validation_certificate_arn
}

# Route53 record for Zulip
resource "aws_route53_record" "zulip" {
  zone_id = var.route53_zone_id
  name    = local.zulip_domain
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# PostgreSQL for Zulip
module "zulip_db" {
  source = "../../../modules/aws/rds-postgres"

  project            = var.project
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  identifier    = "zulip"
  database_name = "zulip"

  allowed_security_group_ids = [module.ecs.tasks_security_group_id]

  # Dev settings
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  multi_az            = false
  deletion_protection = false
  skip_final_snapshot = true
}

# Redis for Zulip
module "zulip_redis" {
  source = "../../../modules/aws/elasticache-redis"

  project            = var.project
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  identifier = "zulip"

  allowed_security_group_ids = [module.ecs.tasks_security_group_id]

  # Dev settings
  node_type = "cache.t3.micro"
}

# S3 bucket for Zulip uploads
resource "aws_s3_bucket" "zulip_uploads" {
  bucket = "${var.project}-${var.environment}-zulip-uploads"

  tags = {
    Name = "${var.project}-${var.environment}-zulip-uploads"
  }
}

resource "aws_s3_bucket_public_access_block" "zulip_uploads" {
  bucket = aws_s3_bucket.zulip_uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "zulip_uploads" {
  bucket = aws_s3_bucket.zulip_uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# SES SMTP user for Zulip email
module "zulip_ses_user" {
  source = "../../../modules/aws/ses-smtp-user"

  name = "${var.project}-${var.environment}-zulip-ses"
  tags = {
    Name = "${var.project}-${var.environment}-zulip-ses"
  }
}

# Zulip secrets
resource "random_password" "zulip_secret_key" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "zulip_secrets" {
  name        = "${var.project}-${var.environment}-zulip-secrets"
  description = "Zulip application secrets"

  tags = {
    Name = "${var.project}-${var.environment}-zulip-secrets"
  }
}

resource "aws_secretsmanager_secret_version" "zulip_secrets" {
  secret_id = aws_secretsmanager_secret.zulip_secrets.id
  secret_string = jsonencode({
    secret_key = random_password.zulip_secret_key.result
  })
}

# IAM policy for Zulip task to access S3
resource "aws_iam_role_policy" "zulip_s3_access" {
  name = "${var.project}-${var.environment}-zulip-s3-access"
  role = module.ecs.task_role_name

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
          aws_s3_bucket.zulip_uploads.arn,
          "${aws_s3_bucket.zulip_uploads.arn}/*"
        ]
      }
    ]
  })
}

# Security group rule for Zulip port
resource "aws_security_group_rule" "ecs_from_alb_zulip" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = module.alb.security_group_id
  security_group_id        = module.ecs.tasks_security_group_id
  description              = "Allow HTTPS from ALB to Zulip"
}

# Add Zulip secrets to ECS execution role
resource "aws_iam_role_policy" "ecs_zulip_secrets_access" {
  name = "${var.project}-${var.environment}-ecs-zulip-secrets"
  role = module.ecs.task_execution_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.zulip_secrets.arn
        ]
      }
    ]
  })
}

# Zulip ECS Service
module "zulip_service" {
  source = "../../../modules/aws/ecs-service"

  project     = var.project
  environment = var.environment

  service_name = "zulip"
  cluster_id   = module.ecs.cluster_id
  vpc_id       = module.vpc.vpc_id

  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_ids = [module.ecs.tasks_security_group_id]

  task_execution_role_arn = module.ecs.task_execution_role_arn
  task_role_arn           = module.ecs.task_role_arn

  container_image = "zulip/docker-zulip:latest"
  container_port  = 443

  cpu    = 1024
  memory = 2048

  environment_variables = {
    # Zulip settings
    SETTING_EXTERNAL_HOST       = local.zulip_domain
    SETTING_ZULIP_ADMINISTRATOR = "admin@${var.domain_name}"
    DISABLE_HTTPS               = "true" # ALB handles HTTPS termination

    # Database
    SETTING_DATABASES__default__HOST = module.zulip_db.address
    SETTING_DATABASES__default__NAME = module.zulip_db.database_name
    SETTING_DATABASES__default__USER = module.zulip_db.master_username

    # Redis
    SETTING_REDIS_HOST = module.zulip_redis.endpoint
    SETTING_REDIS_PORT = tostring(module.zulip_redis.port)

    # S3 storage
    SETTING_LOCAL_UPLOADS_DIR   = ""
    SETTING_S3_AUTH_UPLOADS_BUCKET = aws_s3_bucket.zulip_uploads.id
    SETTING_S3_REGION           = var.region

    # Email (SES)
    SETTING_EMAIL_HOST          = "email-smtp.${var.region}.amazonaws.com"
    SETTING_EMAIL_HOST_USER     = module.zulip_ses_user.name
    SETTING_EMAIL_PORT          = "587"
    SETTING_EMAIL_USE_TLS       = "true"
    SETTING_NOREPLY_EMAIL_ADDRESS = "noreply@${var.domain_name}"

    # SSO via Zitadel (configure after Zitadel is running)
    # SOCIAL_AUTH_OIDC_ENABLED_IDPS will be configured via Zulip admin
    SETTING_AUTHENTICATION_BACKENDS = "zproject.backends.GenericOpenIdConnectBackend"
  }

  secrets = {
    SECRETS_postgres_password = "${module.zulip_db.master_password_secret_arn}:password::"
    SECRETS_secret_key        = "${aws_secretsmanager_secret.zulip_secrets.arn}:secret_key::"
  }

  # ALB Integration
  create_alb_target_group = true
  alb_listener_arn        = module.alb.https_listener_arn
  host_header             = local.zulip_domain
  listener_rule_priority  = 200
  health_check_path       = "/health"
  health_check_matcher    = "200"
}
