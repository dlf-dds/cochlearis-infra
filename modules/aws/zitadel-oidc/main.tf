# Zitadel OIDC Applications Module
#
# Creates OIDC applications in Zitadel for SSO integration with other services.
# Requires Zitadel to be running and a service account key for authentication.

terraform {
  required_providers {
    zitadel = {
      source  = "zitadel/zitadel"
      version = "~> 2.0"
    }
  }
}

# Create project for all cochlearis applications
resource "zitadel_project" "main" {
  name                     = var.project_name
  org_id                   = var.organization_id
  project_role_assertion   = true
  project_role_check       = true
  has_project_check        = true
  private_labeling_setting = "PRIVATE_LABELING_SETTING_UNSPECIFIED"
}

# =============================================================================
# BookStack OIDC Application
# =============================================================================

resource "zitadel_application_oidc" "bookstack" {
  project_id = zitadel_project.main.id
  org_id     = var.organization_id

  name = "BookStack"

  redirect_uris        = ["https://${var.bookstack_domain}/oidc/callback"]
  post_logout_redirect_uris = ["https://${var.bookstack_domain}/"]

  response_types             = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types                = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"]
  app_type                   = "OIDC_APP_TYPE_WEB"
  auth_method_type           = "OIDC_AUTH_METHOD_TYPE_BASIC"
  access_token_type          = "OIDC_TOKEN_TYPE_BEARER"
  access_token_role_assertion = true
  id_token_role_assertion    = true
  id_token_userinfo_assertion = true
  dev_mode                   = false

  clock_skew                          = "0s"
  additional_origins                  = []
  skip_native_app_success_page        = false
}

# Store BookStack OIDC credentials in Secrets Manager
resource "aws_secretsmanager_secret" "bookstack_oidc" {
  name        = "${var.secret_prefix}-bookstack-oidc"
  description = "BookStack OIDC client credentials from Zitadel"

  tags = {
    Name = "${var.secret_prefix}-bookstack-oidc"
  }
}

resource "aws_secretsmanager_secret_version" "bookstack_oidc" {
  secret_id = aws_secretsmanager_secret.bookstack_oidc.id
  secret_string = jsonencode({
    client_id     = zitadel_application_oidc.bookstack.client_id
    client_secret = zitadel_application_oidc.bookstack.client_secret
  })
}

# =============================================================================
# Zulip OIDC Application
# =============================================================================

resource "zitadel_application_oidc" "zulip" {
  project_id = zitadel_project.main.id
  org_id     = var.organization_id

  name = "Zulip"

  redirect_uris        = ["https://${var.zulip_domain}/complete/oidc/"]
  post_logout_redirect_uris = ["https://${var.zulip_domain}/"]

  response_types             = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types                = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"]
  app_type                   = "OIDC_APP_TYPE_WEB"
  auth_method_type           = "OIDC_AUTH_METHOD_TYPE_BASIC"
  access_token_type          = "OIDC_TOKEN_TYPE_BEARER"
  access_token_role_assertion = true
  id_token_role_assertion    = true
  id_token_userinfo_assertion = true
  dev_mode                   = false

  clock_skew                          = "0s"
  additional_origins                  = []
  skip_native_app_success_page        = false
}

# Store Zulip OIDC credentials in Secrets Manager
resource "aws_secretsmanager_secret" "zulip_oidc" {
  name        = "${var.secret_prefix}-zulip-oidc"
  description = "Zulip OIDC client credentials from Zitadel"

  tags = {
    Name = "${var.secret_prefix}-zulip-oidc"
  }
}

resource "aws_secretsmanager_secret_version" "zulip_oidc" {
  secret_id = aws_secretsmanager_secret.zulip_oidc.id
  secret_string = jsonencode({
    client_id     = zitadel_application_oidc.zulip.client_id
    client_secret = zitadel_application_oidc.zulip.client_secret
  })
}

# =============================================================================
# Mattermost OIDC Application
# =============================================================================

resource "zitadel_application_oidc" "mattermost" {
  project_id = zitadel_project.main.id
  org_id     = var.organization_id

  name = "Mattermost"

  # Mattermost Team Edition uses GitLab-style OAuth callback
  redirect_uris             = ["https://${var.mattermost_domain}/signup/gitlab/complete"]
  post_logout_redirect_uris = ["https://${var.mattermost_domain}/"]

  response_types              = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types                 = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"]
  app_type                    = "OIDC_APP_TYPE_WEB"
  auth_method_type            = "OIDC_AUTH_METHOD_TYPE_BASIC"
  access_token_type           = "OIDC_TOKEN_TYPE_BEARER"
  access_token_role_assertion = true
  id_token_role_assertion     = true
  id_token_userinfo_assertion = true
  dev_mode                    = false

  clock_skew                   = "0s"
  additional_origins           = []
  skip_native_app_success_page = false
}

# Store Mattermost OIDC credentials in Secrets Manager
resource "aws_secretsmanager_secret" "mattermost_oidc" {
  name        = "${var.secret_prefix}-mattermost-oidc"
  description = "Mattermost OIDC client credentials from Zitadel"

  tags = {
    Name = "${var.secret_prefix}-mattermost-oidc"
  }
}

resource "aws_secretsmanager_secret_version" "mattermost_oidc" {
  secret_id = aws_secretsmanager_secret.mattermost_oidc.id
  secret_string = jsonencode({
    client_id     = zitadel_application_oidc.mattermost.client_id
    client_secret = zitadel_application_oidc.mattermost.client_secret
  })
}
