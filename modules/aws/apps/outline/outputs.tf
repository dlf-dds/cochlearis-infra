output "url" {
  description = "URL for Outline"
  value       = "https://${local.domain}"
}

output "domain" {
  description = "Domain name for Outline"
  value       = local.domain
}

output "db_endpoint" {
  description = "Database endpoint"
  value       = module.database.endpoint
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
