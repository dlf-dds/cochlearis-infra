output "url" {
  description = "Zulip Mini URL"
  value       = "https://${local.domain}"
}

output "domain" {
  description = "Zulip Mini domain"
  value       = local.domain
}

output "efs_file_system_id" {
  description = "EFS file system ID"
  value       = module.efs.file_system_id
}
