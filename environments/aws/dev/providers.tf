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

# Note: Zitadel OIDC configuration is in dev/oidc/ - a separate Terraform root.
# This avoids chicken-and-egg problems where the zitadel provider needs
# Zitadel to be running before it can initialize.
