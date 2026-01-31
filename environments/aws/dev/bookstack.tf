# BookStack Documentation Platform Deployment
#
# Self-hosted BookStack wiki with SSO via Zitadel

locals {
  bookstack_domain = "docs.dev.${var.domain_name}"
}

# SSL Certificate for BookStack
module "bookstack_certificate" {
  source = "../../../modules/aws/acm-certificate"

  project     = var.project
  environment = var.environment
  domain_name = local.bookstack_domain
  zone_id     = var.route53_zone_id
}

# Add BookStack certificate to ALB
resource "aws_lb_listener_certificate" "bookstack" {
  listener_arn    = module.alb.https_listener_arn
  certificate_arn = module.bookstack_certificate.validation_certificate_arn
}

# Route53 record for BookStack
resource "aws_route53_record" "bookstack" {
  zone_id = var.route53_zone_id
  name    = local.bookstack_domain
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# MySQL for BookStack (BookStack works best with MySQL/MariaDB)
module "bookstack_db" {
  source = "../../../modules/aws/rds-postgres"

  project            = var.project
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  identifier    = "bookstack"
  database_name = "bookstack"

  allowed_security_group_ids = [module.ecs.tasks_security_group_id]

  # Dev settings
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  multi_az            = false
  deletion_protection = false
  skip_final_snapshot = true
}

# BookStack app key secret
resource "random_password" "bookstack_app_key" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "bookstack_app_key" {
  name        = "${var.project}-${var.environment}-bookstack-app-key"
  description = "BookStack Laravel application key"

  tags = {
    Name = "${var.project}-${var.environment}-bookstack-app-key"
  }
}

resource "aws_secretsmanager_secret_version" "bookstack_app_key" {
  secret_id     = aws_secretsmanager_secret.bookstack_app_key.id
  secret_string = "base64:${base64encode(random_password.bookstack_app_key.result)}"
}

# S3 bucket for BookStack uploads
resource "aws_s3_bucket" "bookstack_uploads" {
  bucket = "${var.project}-${var.environment}-bookstack-uploads"

  tags = {
    Name = "${var.project}-${var.environment}-bookstack-uploads"
  }
}

resource "aws_s3_bucket_public_access_block" "bookstack_uploads" {
  bucket = aws_s3_bucket.bookstack_uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bookstack_uploads" {
  bucket = aws_s3_bucket.bookstack_uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# IAM policy for BookStack task to access S3
resource "aws_iam_role_policy" "bookstack_s3_access" {
  name = "${var.project}-${var.environment}-bookstack-s3-access"
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
          aws_s3_bucket.bookstack_uploads.arn,
          "${aws_s3_bucket.bookstack_uploads.arn}/*"
        ]
      }
    ]
  })
}

# Security group rule for BookStack port
resource "aws_security_group_rule" "ecs_from_alb_bookstack" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = module.alb.security_group_id
  security_group_id        = module.ecs.tasks_security_group_id
  description              = "Allow HTTP from ALB to BookStack"
}

# Add BookStack secrets to ECS execution role
resource "aws_iam_role_policy" "ecs_bookstack_secrets_access" {
  name = "${var.project}-${var.environment}-ecs-bookstack-secrets"
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
          aws_secretsmanager_secret.bookstack_app_key.arn,
          module.bookstack_db.master_password_secret_arn
        ]
      }
    ]
  })
}

# BookStack ECS Service
module "bookstack_service" {
  source = "../../../modules/aws/ecs-service"

  project     = var.project
  environment = var.environment

  service_name = "bookstack"
  cluster_id   = module.ecs.cluster_id
  vpc_id       = module.vpc.vpc_id

  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_ids = [module.ecs.tasks_security_group_id]

  task_execution_role_arn = module.ecs.task_execution_role_arn
  task_role_arn           = module.ecs.task_role_arn

  container_image = "lscr.io/linuxserver/bookstack:latest"
  container_port  = 80

  cpu    = 512
  memory = 1024

  environment_variables = {
    # App settings
    APP_URL = "https://${local.bookstack_domain}"
    APP_ENV = "production"

    # Database (using PostgreSQL)
    DB_CONNECTION = "pgsql"
    DB_HOST       = module.bookstack_db.address
    DB_PORT       = tostring(module.bookstack_db.port)
    DB_DATABASE   = module.bookstack_db.database_name
    DB_USERNAME   = module.bookstack_db.master_username

    # Session and cache
    SESSION_DRIVER       = "database"
    CACHE_DRIVER         = "database"
    SESSION_SECURE_COOKIE = "true"

    # File storage (local for now, can switch to S3)
    STORAGE_TYPE = "local"

    # Mail settings (using SES via Zulip's SES user or configure separate)
    MAIL_DRIVER   = "smtp"
    MAIL_HOST     = "email-smtp.${var.region}.amazonaws.com"
    MAIL_PORT     = "587"
    MAIL_FROM     = "docs@${var.domain_name}"
    MAIL_FROM_NAME = "BookStack"
    MAIL_ENCRYPTION = "tls"

    # OIDC SSO via Zitadel (configure after Zitadel is running)
    AUTH_METHOD                    = "oidc"
    OIDC_NAME                      = "Zitadel"
    OIDC_DISPLAY_NAME_CLAIMS       = "name"
    OIDC_CLIENT_ID                 = "" # Configure after Zitadel setup
    OIDC_ISSUER                    = "https://auth.dev.${var.domain_name}"
    OIDC_ISSUER_DISCOVER           = "true"
    OIDC_USER_TO_GROUPS            = "true"
    OIDC_GROUPS_CLAIM              = "groups"
    OIDC_REMOVE_FROM_GROUPS        = "true"
  }

  secrets = {
    DB_PASSWORD = "${module.bookstack_db.master_password_secret_arn}:password::"
    APP_KEY     = aws_secretsmanager_secret.bookstack_app_key.arn
  }

  # ALB Integration
  create_alb_target_group = true
  alb_listener_arn        = module.alb.https_listener_arn
  host_header             = local.bookstack_domain
  listener_rule_priority  = 300
  health_check_path       = "/status"
  health_check_matcher    = "200"
}
