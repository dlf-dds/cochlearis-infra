# Zitadel OIDC Module Outputs

output "project_id" {
  description = "Zitadel project ID"
  value       = zitadel_project.main.id
}

# BookStack
output "bookstack_client_id" {
  description = "BookStack OIDC client ID"
  value       = zitadel_application_oidc.bookstack.client_id
}

output "bookstack_oidc_secret_arn" {
  description = "ARN of the BookStack OIDC credentials secret"
  value       = aws_secretsmanager_secret.bookstack_oidc.arn
}

# Zulip
output "zulip_client_id" {
  description = "Zulip OIDC client ID"
  value       = zitadel_application_oidc.zulip.client_id
}

output "zulip_oidc_secret_arn" {
  description = "ARN of the Zulip OIDC credentials secret"
  value       = aws_secretsmanager_secret.zulip_oidc.arn
}

# Mattermost
output "mattermost_client_id" {
  description = "Mattermost OIDC client ID"
  value       = zitadel_application_oidc.mattermost.client_id
}

output "mattermost_oidc_secret_arn" {
  description = "ARN of the Mattermost OIDC credentials secret"
  value       = aws_secretsmanager_secret.mattermost_oidc.arn
}
