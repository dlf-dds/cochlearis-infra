output "zitadel_project_id" {
  description = "Zitadel project ID"
  value       = module.zitadel_oidc.project_id
  sensitive   = true
}

output "bookstack_client_id" {
  description = "BookStack OIDC client ID"
  value       = module.zitadel_oidc.bookstack_client_id
  sensitive   = true
}

output "mattermost_client_id" {
  description = "Mattermost OIDC client ID"
  value       = module.zitadel_oidc.mattermost_client_id
  sensitive   = true
}

output "zulip_client_id" {
  description = "Zulip OIDC client ID"
  value       = module.zitadel_oidc.zulip_client_id
  sensitive   = true
}

output "outline_client_id" {
  description = "Outline OIDC client ID"
  value       = module.zitadel_oidc.outline_client_id
  sensitive   = true
}
