output "endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = aws_db_instance.main.endpoint
}

output "address" {
  description = "The hostname of the RDS instance"
  value       = aws_db_instance.main.address
}

output "port" {
  description = "The port of the RDS instance"
  value       = aws_db_instance.main.port
}

output "database_name" {
  description = "The name of the database"
  value       = aws_db_instance.main.db_name
}

output "master_username" {
  description = "The master username"
  value       = aws_db_instance.main.username
}

output "instance_id" {
  description = "The RDS instance ID"
  value       = aws_db_instance.main.id
}

output "instance_arn" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.main.arn
}

output "security_group_id" {
  description = "The ID of the RDS security group"
  value       = aws_security_group.rds.id
}

output "master_password_secret_arn" {
  description = "The ARN of the Secrets Manager secret containing the master password"
  value       = aws_secretsmanager_secret.master_password.arn
}

output "master_password_secret_name" {
  description = "The name of the Secrets Manager secret containing the master password"
  value       = aws_secretsmanager_secret.master_password.name
}
