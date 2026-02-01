output "url" {
  description = "URL for Zitadel"
  value       = "https://${local.domain}"
}

output "domain" {
  description = "Domain name for Zitadel"
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

output "admin_credentials_secret_arn" {
  description = "ARN of the secret containing admin credentials (key: admin_password)"
  value       = aws_secretsmanager_secret.master_key.arn
}

output "admin_username" {
  description = "Admin username for initial login"
  value       = var.admin_username
}

output "target_group_arn" {
  description = "ARN of the target group for Zitadel ECS service"
  value       = module.service.target_group_arn
}
