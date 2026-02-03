# =============================================================================
# Zitadel OIDC Applications
# =============================================================================
#
# This is a separate Terraform root to avoid chicken-and-egg problems.
# The zitadel provider requires Zitadel to be running, but Zitadel is created
# by the main dev/ configuration.
#
# Deploy order:
#   1. terraform apply in dev/     -> Creates infrastructure including Zitadel
#   2. terraform apply in dev/oidc -> Creates OIDC clients (this file)
#   3. terraform apply in dev/     -> Apps pick up OIDC config from SSM
#
# =============================================================================

locals {
  name_prefix = "${var.project}-${var.environment}"
}

# Read organization ID from SSM (created by bootstrap script)
data "aws_ssm_parameter" "zitadel_org_id" {
  name = "/${var.project}/${var.environment}/zitadel/organization-id"
}

# Create OIDC applications in Zitadel
module "zitadel_oidc" {
  source = "../../../../modules/aws/zitadel-oidc"

  organization_id   = data.aws_ssm_parameter.zitadel_org_id.value
  project_name      = "Cochlearis"
  secret_prefix     = local.name_prefix
  bookstack_domain  = "docs.${var.environment}.${var.domain_name}"
  zulip_domain      = "chat.${var.environment}.${var.domain_name}"
  mattermost_domain = "mm.${var.environment}.${var.domain_name}"
  outline_domain    = "wiki.${var.environment}.${var.domain_name}"
}

# =============================================================================
# Write OIDC configuration to SSM for main dev/ to consume
# =============================================================================

resource "aws_ssm_parameter" "zitadel_url" {
  name  = "/${var.project}/${var.environment}/oidc/issuer-url"
  type  = "String"
  value = "https://auth.${var.environment}.${var.domain_name}"
}

# BookStack
resource "aws_ssm_parameter" "bookstack_client_id" {
  name  = "/${var.project}/${var.environment}/oidc/bookstack/client-id"
  type  = "String"
  value = module.zitadel_oidc.bookstack_client_id
}

resource "aws_ssm_parameter" "bookstack_secret_arn" {
  name  = "/${var.project}/${var.environment}/oidc/bookstack/secret-arn"
  type  = "String"
  value = module.zitadel_oidc.bookstack_oidc_secret_arn
}

# Mattermost
resource "aws_ssm_parameter" "mattermost_client_id" {
  name  = "/${var.project}/${var.environment}/oidc/mattermost/client-id"
  type  = "String"
  value = module.zitadel_oidc.mattermost_client_id
}

resource "aws_ssm_parameter" "mattermost_secret_arn" {
  name  = "/${var.project}/${var.environment}/oidc/mattermost/secret-arn"
  type  = "String"
  value = module.zitadel_oidc.mattermost_oidc_secret_arn
}

# Zulip
resource "aws_ssm_parameter" "zulip_client_id" {
  name  = "/${var.project}/${var.environment}/oidc/zulip/client-id"
  type  = "String"
  value = module.zitadel_oidc.zulip_client_id
}

resource "aws_ssm_parameter" "zulip_secret_arn" {
  name  = "/${var.project}/${var.environment}/oidc/zulip/secret-arn"
  type  = "String"
  value = module.zitadel_oidc.zulip_oidc_secret_arn
}

# Outline
resource "aws_ssm_parameter" "outline_client_id" {
  name  = "/${var.project}/${var.environment}/oidc/outline/client-id"
  type  = "String"
  value = module.zitadel_oidc.outline_client_id
}

resource "aws_ssm_parameter" "outline_secret_arn" {
  name  = "/${var.project}/${var.environment}/oidc/outline/secret-arn"
  type  = "String"
  value = module.zitadel_oidc.outline_oidc_secret_arn
}
