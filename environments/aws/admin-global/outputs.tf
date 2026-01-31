output "admin_group_name" {
  description = "Name of the administrators group"
  value       = aws_iam_group.admin.name
}

output "admin_group_arn" {
  description = "ARN of the administrators group"
  value       = aws_iam_group.admin.arn
}

output "alumni_group_name" {
  description = "Name of the alumni group"
  value       = aws_iam_group.alumni.name
}

output "admin_user_arns" {
  description = "ARNs of admin users"
  value       = { for k, v in aws_iam_user.user : k => v.arn if contains(keys(local.admin_users), k) }
}
