# Mattermost Team Chat Module
#
# Self-hosted Mattermost for team communication

locals {
  name_prefix   = "${var.project}-${var.environment}"
  domain        = "${var.subdomain}.${var.environment}.${var.domain_name}"
  oidc_enabled  = var.oidc_client_id != "" && var.oidc_client_secret_arn != ""
  oidc_issuer   = var.oidc_issuer != "" ? var.oidc_issuer : "https://auth.${var.environment}.${var.domain_name}"
  azure_enabled = var.azure_client_id != "" && var.azure_client_secret_arn != "" && var.azure_tenant_id != ""
  smtp_enabled  = var.smtp_from_email != ""
}

# SES SMTP user for sending emails
module "ses_user" {
  count  = local.smtp_enabled ? 1 : 0
  source = "../../ses-smtp-user"

  name = "${local.name_prefix}-mattermost-ses"
  tags = {
    Name        = "${local.name_prefix}-mattermost-ses"
    Environment = var.environment
    Service     = "mattermost"
  }
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

# Add certificate to ALB
resource "aws_lb_listener_certificate" "main" {
  count           = var.create_certificate ? 1 : 0
  listener_arn    = var.alb_listener_arn
  certificate_arn = module.certificate[0].validation_certificate_arn
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

  identifier    = "mattermost"
  database_name = "mattermost"

  allowed_security_group_ids = [var.ecs_tasks_security_group_id]

  instance_class      = var.db_instance_class
  allocated_storage   = var.db_allocated_storage
  multi_az            = var.db_multi_az
  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = var.db_skip_final_snapshot
}

# Random suffix to avoid Secrets Manager name collision on recreate
resource "random_id" "secret_suffix" {
  byte_length = 4
}

# Database connection string secret (Mattermost requires full DSN)
resource "aws_secretsmanager_secret" "database_url" {
  name        = "${local.name_prefix}-mattermost-database-url-${random_id.secret_suffix.hex}"
  description = "Mattermost database connection string"

  tags = {
    Name = "${local.name_prefix}-mattermost-database-url"
  }
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id = aws_secretsmanager_secret.database_url.id
  secret_string = jsonencode({
    dsn = "postgres://${module.database.master_username}:${module.database.master_password}@${module.database.address}:${module.database.port}/${module.database.database_name}?sslmode=require&connect_timeout=10"
  })
}

# IAM policy for secrets access
resource "aws_iam_role_policy" "secrets_access" {
  name = "${local.name_prefix}-mattermost-secrets-access"
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
          [aws_secretsmanager_secret.database_url.arn],
          local.oidc_enabled ? [var.oidc_client_secret_arn] : [],
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

  service_name = "mattermost"
  cluster_id   = var.ecs_cluster_id
  vpc_id       = var.vpc_id

  private_subnet_ids = var.private_subnet_ids
  security_group_ids = [var.ecs_tasks_security_group_id]

  task_execution_role_arn = var.task_execution_role_arn
  task_role_arn           = var.task_role_arn

  container_image = var.container_image
  container_port  = 8065

  cpu           = var.ecs_cpu
  memory        = var.ecs_memory
  desired_count = var.desired_count

  environment_variables = merge(
    {
      # Database driver
      MM_SQLSETTINGS_DRIVERNAME = "postgres"

      # Site settings
      MM_SERVICESETTINGS_SITEURL       = "https://${local.domain}"
      MM_SERVICESETTINGS_LISTENADDRESS = ":8065"
      MM_SERVICESETTINGS_WEBSOCKETURL  = "wss://${local.domain}/api/v4/websocket"

      # Reverse proxy settings (ALB terminates TLS, forwards HTTP to container)
      MM_SERVICESETTINGS_TRUSTEDPROXYIPHEADER    = "X-Forwarded-For"
      MM_SERVICESETTINGS_ALLOWEDUNTRUSTEDINTERNALCONNECTIONS = ""

      # Disable telemetry
      MM_LOGSETTINGS_ENABLEDIAGNOSTICS = "false"

      # Team settings
      MM_TEAMSETTINGS_ENABLEOPENSERVER = var.enable_open_server ? "true" : "false"

      # Email settings
      MM_EMAILSETTINGS_SENDEMAILNOTIFICATIONS   = local.smtp_enabled ? "true" : "false"
      MM_EMAILSETTINGS_REQUIREEMAILVERIFICATION = "false"
    },
    # SMTP settings (SES)
    local.smtp_enabled ? {
      MM_EMAILSETTINGS_SMTPSERVER                    = "email-smtp.${var.region}.amazonaws.com"
      MM_EMAILSETTINGS_SMTPPORT                      = "587"
      MM_EMAILSETTINGS_ENABLESMTPAUTH                = "true"
      MM_EMAILSETTINGS_CONNECTIONSECURITY            = "STARTTLS"
      MM_EMAILSETTINGS_FEEDBACKEMAIL                 = var.smtp_from_email
      MM_EMAILSETTINGS_REPLYTOADDRESS                = var.smtp_from_email
      MM_EMAILSETTINGS_FEEDBACKNAME                  = "Mattermost"
      MM_EMAILSETTINGS_FEEDBACKORGANIZATION          = var.project
      MM_SUPPORTSETTINGS_SUPPORTEMAIL                = var.smtp_from_email
      MM_EMAILSETTINGS_SKIPSERVERCERTIFICATEVERIFICATION = "false"
    } : {},
    # Authentication: Azure AD (Office 365) > OIDC (abandoned) > Email/password
    local.azure_enabled ? {
      # Office 365 / Azure AD OAuth - available in Team Edition
      MM_OFFICE365SETTINGS_ENABLE          = "true"
      MM_OFFICE365SETTINGS_ID              = var.azure_client_id
      MM_OFFICE365SETTINGS_SCOPE           = "User.Read"
      MM_OFFICE365SETTINGS_AUTHENDPOINT    = "https://login.microsoftonline.com/${var.azure_tenant_id}/oauth2/v2.0/authorize"
      MM_OFFICE365SETTINGS_TOKENENDPOINT   = "https://login.microsoftonline.com/${var.azure_tenant_id}/oauth2/v2.0/token"
      MM_OFFICE365SETTINGS_USERAPIENDPOINT = "https://graph.microsoft.com/v1.0/me"
      MM_OFFICE365SETTINGS_DIRECTORYTID    = var.azure_tenant_id
    } : local.oidc_enabled ? {
      # OpenID Connect SSO via Zitadel (Team Edition uses GitLab-style OAuth adapter)
      # Note: Team Edition requires "read_user" scope, NOT standard OIDC scopes
      MM_GITLABSETTINGS_ENABLE          = "true"
      MM_GITLABSETTINGS_ID              = var.oidc_client_id
      MM_GITLABSETTINGS_SCOPE           = "read_user"
      MM_GITLABSETTINGS_AUTHENDPOINT    = "${local.oidc_issuer}/oauth/v2/authorize"
      MM_GITLABSETTINGS_TOKENENDPOINT   = "${local.oidc_issuer}/oauth/v2/token"
      MM_GITLABSETTINGS_USERAPIENDPOINT = "${local.oidc_issuer}/oidc/v1/userinfo"
    } : {}
  )

  secrets = merge(
    {
      # Database connection string (full DSN with password)
      MM_SQLSETTINGS_DATASOURCE = "${aws_secretsmanager_secret.database_url.arn}:dsn::"
    },
    local.azure_enabled ? {
      MM_OFFICE365SETTINGS_SECRET = "${var.azure_client_secret_arn}:client_secret::"
    } : {},
    local.oidc_enabled && !local.azure_enabled ? {
      MM_GITLABSETTINGS_SECRET = "${var.oidc_client_secret_arn}:client_secret::"
    } : {},
    local.smtp_enabled ? {
      MM_EMAILSETTINGS_SMTPUSERNAME = "${module.ses_user[0].smtp_credentials_secret_arn}:username::"
      MM_EMAILSETTINGS_SMTPPASSWORD = "${module.ses_user[0].smtp_credentials_secret_arn}:password::"
    } : {}
  )

  # ALB Integration
  create_alb_target_group = true
  alb_listener_arn        = var.alb_listener_arn
  host_header             = local.domain
  listener_rule_priority  = var.listener_rule_priority
  health_check_path       = "/api/v4/system/ping"
  health_check_matcher    = "200"
}
