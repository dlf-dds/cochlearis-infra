variable "project" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "Number of days to retain CloudTrail logs in S3 before deletion"
  type        = number
  default     = 365
}

variable "is_multi_region" {
  description = "Whether the trail should be multi-region"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch Logs integration for real-time alerting"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 90
}

variable "log_s3_data_events" {
  description = "Log S3 data events (object-level operations). This can significantly increase costs."
  type        = bool
  default     = false
}
