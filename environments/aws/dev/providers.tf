provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "cochlearis-infra"
      Owner       = var.owner_email
      Lifecycle   = "persistent" # Override with "temporary" for short-lived resources
    }
  }
}

# Zitadel provider for OIDC application management
# Note: This requires the bootstrap script to have been run first
data "aws_secretsmanager_secret_version" "zitadel_service_account" {
  count     = var.enable_zitadel_oidc ? 1 : 0
  secret_id = "${var.project}-${var.environment}-zitadel-service-account"
}

provider "zitadel" {
  domain           = "auth.${var.environment}.${var.domain_name}"
  insecure         = false
  port             = 443
  jwt_profile_json = var.enable_zitadel_oidc ? data.aws_secretsmanager_secret_version.zitadel_service_account[0].secret_string : "{}"
}
