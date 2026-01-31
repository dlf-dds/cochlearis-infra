# Zitadel Identity Provider Deployment
#
# Self-hosted Zitadel for SSO authentication

locals {
  zitadel_domain = "auth.dev.${var.domain_name}"
}

# SSL Certificate for Zitadel
module "zitadel_certificate" {
  source = "../../../modules/aws/acm-certificate"

  project     = var.project
  environment = var.environment
  domain_name = local.zitadel_domain
  zone_id     = var.route53_zone_id
}

# Shared ALB for all services
module "alb" {
  source = "../../../modules/aws/alb"

  project           = var.project
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  certificate_arn   = module.zitadel_certificate.validation_certificate_arn
}

# Route53 record for Zitadel
resource "aws_route53_record" "zitadel" {
  zone_id = var.route53_zone_id
  name    = local.zitadel_domain
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# PostgreSQL for Zitadel
module "zitadel_db" {
  source = "../../../modules/aws/rds-postgres"

  project            = var.project
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  identifier    = "zitadel"
  database_name = "zitadel"

  allowed_security_group_ids = [module.ecs.tasks_security_group_id]

  # Dev settings
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  multi_az            = false
  deletion_protection = false
  skip_final_snapshot = true
}

# Zitadel master key secret
resource "random_password" "zitadel_master_key" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "zitadel_master_key" {
  name        = "${var.project}-${var.environment}-zitadel-master-key"
  description = "Zitadel master key for encryption"

  tags = {
    Name = "${var.project}-${var.environment}-zitadel-master-key"
  }
}

resource "aws_secretsmanager_secret_version" "zitadel_master_key" {
  secret_id     = aws_secretsmanager_secret.zitadel_master_key.id
  secret_string = random_password.zitadel_master_key.result
}

# Security group rule to allow ALB to reach ECS tasks
resource "aws_security_group_rule" "ecs_from_alb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = module.alb.security_group_id
  security_group_id        = module.ecs.tasks_security_group_id
  description              = "Allow traffic from ALB to ECS tasks"
}

# IAM policy for ECS tasks to read secrets
resource "aws_iam_role_policy" "ecs_secrets_access" {
  name = "${var.project}-${var.environment}-ecs-secrets-access"
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
          aws_secretsmanager_secret.zitadel_master_key.arn,
          module.zitadel_db.master_password_secret_arn,
          module.zulip_db.master_password_secret_arn
        ]
      }
    ]
  })
}

# Zitadel ECS Service
module "zitadel_service" {
  source = "../../../modules/aws/ecs-service"

  project     = var.project
  environment = var.environment

  service_name = "zitadel"
  cluster_id   = module.ecs.cluster_id
  vpc_id       = module.vpc.vpc_id

  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_ids = [module.ecs.tasks_security_group_id]

  task_execution_role_arn = module.ecs.task_execution_role_arn
  task_role_arn           = module.ecs.task_role_arn

  container_image = "ghcr.io/zitadel/zitadel:latest"
  container_port  = 8080

  cpu    = 512
  memory = 1024

  environment_variables = {
    ZITADEL_DATABASE_POSTGRES_HOST     = module.zitadel_db.address
    ZITADEL_DATABASE_POSTGRES_PORT     = tostring(module.zitadel_db.port)
    ZITADEL_DATABASE_POSTGRES_DATABASE = module.zitadel_db.database_name
    ZITADEL_DATABASE_POSTGRES_USER     = module.zitadel_db.master_username
    ZITADEL_DATABASE_POSTGRES_SSL_MODE = "require"
    ZITADEL_EXTERNALSECURE             = "true"
    ZITADEL_EXTERNALDOMAIN             = local.zitadel_domain
    ZITADEL_EXTERNALPORT               = "443"
    ZITADEL_FIRSTINSTANCE_ORG_HUMAN_USERNAME = "admin"
  }

  secrets = {
    ZITADEL_DATABASE_POSTGRES_PASSWORD = "${module.zitadel_db.master_password_secret_arn}:password::"
    ZITADEL_MASTERKEY                  = aws_secretsmanager_secret.zitadel_master_key.arn
  }

  # ALB Integration
  create_alb_target_group = true
  alb_listener_arn        = module.alb.https_listener_arn
  host_header             = local.zitadel_domain
  listener_rule_priority  = 100
  health_check_path       = "/debug/healthz"
  health_check_matcher    = "200"
}
