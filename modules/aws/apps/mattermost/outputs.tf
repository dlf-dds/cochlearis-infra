output "url" {
  description = "URL for Mattermost"
  value       = "https://${local.domain}"
}

output "domain" {
  description = "Domain name for Mattermost"
  value       = local.domain
}

output "db_endpoint" {
  description = "Database endpoint"
  value       = module.database.endpoint
}

output "db_address" {
  description = "Database address"
  value       = module.database.address
}

output "certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = var.create_certificate ? module.certificate[0].certificate_arn : var.certificate_arn
}

output "certificate_validation_arn" {
  description = "ARN of the validated ACM certificate"
  value       = var.create_certificate ? module.certificate[0].validation_certificate_arn : var.certificate_arn
}
