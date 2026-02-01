# EFS Module Outputs

output "file_system_id" {
  description = "ID of the EFS filesystem"
  value       = aws_efs_file_system.main.id
}

output "file_system_arn" {
  description = "ARN of the EFS filesystem"
  value       = aws_efs_file_system.main.arn
}

output "access_point_id" {
  description = "ID of the EFS access point"
  value       = aws_efs_access_point.main.id
}

output "access_point_arn" {
  description = "ARN of the EFS access point"
  value       = aws_efs_access_point.main.arn
}

output "security_group_id" {
  description = "Security group ID for EFS mount targets"
  value       = aws_security_group.efs.id
}

output "mount_target_ids" {
  description = "IDs of the EFS mount targets"
  value       = aws_efs_mount_target.main[*].id
}

output "dns_name" {
  description = "DNS name of the EFS filesystem"
  value       = aws_efs_file_system.main.dns_name
}
