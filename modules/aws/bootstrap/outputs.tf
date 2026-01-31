output "s3_bucket_name" {
  description = "The name of the S3 bucket for Terraform state"
  value       = module.s3_tf_state.id
}

output "s3_bucket_arn" {
  description = "The ARN of the S3 bucket for Terraform state"
  value       = module.s3_tf_state.arn
}

output "s3_logs_bucket_name" {
  description = "The name of the S3 bucket for state logs"
  value       = module.s3_tf_state_logs.id
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.tf_state_lock.name
}

output "dynamodb_table_arn" {
  description = "The ARN of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.tf_state_lock.arn
}

output "kms_key_arn" {
  description = "The ARN of the KMS key for S3 encryption"
  value       = module.s3_kms_key.aws_kms_key_arn
}
