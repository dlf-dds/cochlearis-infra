output "url" {
  description = "URL for Zulip"
  value       = "https://${local.domain}"
}

output "domain" {
  description = "Domain name for Zulip"
  value       = local.domain
}

output "db_endpoint" {
  description = "Database endpoint (localhost sidecar)"
  value       = "localhost:5432"
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.redis.endpoint
}

output "uploads_bucket" {
  description = "S3 bucket for uploads"
  value       = aws_s3_bucket.uploads.id
}

output "certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = module.certificate.certificate_arn
}

output "efs_file_system_id" {
  description = "EFS filesystem ID"
  value       = module.efs.file_system_id
}
