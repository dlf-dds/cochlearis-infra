# Mattermost <-> Outline Bridge Module Variables

variable "project" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "domain_name" {
  description = "Root domain name (e.g., almondbread.org)"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS records"
  type        = string
}

# Outline configuration
variable "outline_api_key_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Outline API key (JSON with 'api_key' field)"
  type        = string
}

variable "outline_collection_id" {
  description = "Default Outline collection ID for new documents created via slash command"
  type        = string
}

variable "outline_base_url" {
  description = "Outline base URL (e.g., https://wiki.dev.almondbread.org)"
  type        = string
  default     = ""
}

# Mattermost configuration
variable "mattermost_webhook_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Mattermost incoming webhook URL (JSON with 'webhook_url' field)"
  type        = string
}

# Lambda configuration
variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory" {
  description = "Lambda function memory in MB"
  type        = number
  default     = 128
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
