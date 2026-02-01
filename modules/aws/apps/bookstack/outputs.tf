output "url" {
  description = "URL for BookStack"
  value       = "https://${local.domain}"
}

output "domain" {
  description = "Domain name for BookStack"
  value       = local.domain
}

output "db_endpoint" {
  description = "Database endpoint"
  value       = module.database.endpoint
}

output "uploads_bucket" {
  description = "S3 bucket for uploads"
  value       = aws_s3_bucket.uploads.id
}

output "certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = module.certificate.certificate_arn
}
