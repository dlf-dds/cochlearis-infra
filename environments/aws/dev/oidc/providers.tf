provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "cochlearis-infra"
    }
  }
}

# Zitadel provider for OIDC application management
data "aws_secretsmanager_secret_version" "zitadel_service_account" {
  secret_id = "${var.project}-${var.environment}-zitadel-service-account"
}

provider "zitadel" {
  domain           = "auth.${var.environment}.${var.domain_name}"
  insecure         = false
  port             = 443
  jwt_profile_json = data.aws_secretsmanager_secret_version.zitadel_service_account.secret_string
}
