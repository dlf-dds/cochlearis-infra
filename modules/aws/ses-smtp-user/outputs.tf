output "name" {
  description = "The name of the IAM user"
  value       = aws_iam_user.main.name
}

output "arn" {
  description = "The ARN of the IAM user"
  value       = aws_iam_user.main.arn
}

output "policy_arn" {
  description = "The ARN of the IAM policy attached to the user"
  value       = aws_iam_policy.main.arn
}

output "smtp_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing SMTP credentials"
  value       = aws_secretsmanager_secret.smtp_credentials.arn
}

output "smtp_endpoint" {
  description = "SES SMTP endpoint for the current region"
  value       = "email-smtp.${data.aws_region.current.name}.amazonaws.com"
}
