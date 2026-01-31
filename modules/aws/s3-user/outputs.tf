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
