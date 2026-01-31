output "certificate_arn" {
  description = "The ARN of the ACM certificate"
  value       = aws_acm_certificate.main.arn
}

output "certificate_id" {
  description = "The ID of the ACM certificate"
  value       = aws_acm_certificate.main.id
}

output "domain_name" {
  description = "The domain name of the certificate"
  value       = aws_acm_certificate.main.domain_name
}

output "validation_certificate_arn" {
  description = "The ARN of the validated certificate (use this for ALB)"
  value       = aws_acm_certificate_validation.main.certificate_arn
}
