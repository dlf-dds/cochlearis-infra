# Zulip EC2 Outputs

output "url" {
  description = "URL to access Zulip"
  value       = "https://${local.domain}"
}

output "domain" {
  description = "Domain name for Zulip"
  value       = local.domain
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.zulip.id
}

output "private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.zulip.private_ip
}

output "security_group_id" {
  description = "Security group ID for the EC2 instance"
  value       = aws_security_group.zulip.id
}

output "target_group_arn" {
  description = "ARN of the ALB target group"
  value       = aws_lb_target_group.zulip.arn
}

output "secrets_arn" {
  description = "ARN of the Secrets Manager secret containing Zulip credentials"
  value       = aws_secretsmanager_secret.zulip.arn
}
