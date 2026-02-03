# Mattermost App Module Variables

variable "project" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "domain_name" {
  description = "Root domain name (e.g., example.com)"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

# Network
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

# ALB
variable "alb_dns_name" {
  description = "DNS name of the ALB"
  type        = string
}

variable "alb_zone_id" {
  description = "Route53 zone ID of the ALB"
  type        = string
}

variable "alb_listener_arn" {
  description = "ARN of the ALB HTTPS listener"
  type        = string
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB"
  type        = string
}

# ECS
variable "ecs_cluster_id" {
  description = "ECS cluster ID"
  type        = string
}

variable "ecs_tasks_security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  type        = string
}

variable "task_execution_role_name" {
  description = "Name of the ECS task execution role"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS task role"
  type        = string
}

# Database configuration
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = false
}

variable "db_deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip final snapshot when destroying"
  type        = bool
  default     = true
}

# ECS configuration
variable "ecs_cpu" {
  description = "CPU units for the ECS task"
  type        = number
  default     = 512
}

variable "ecs_memory" {
  description = "Memory in MB for the ECS task"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 1
}

variable "listener_rule_priority" {
  description = "Priority for the ALB listener rule"
  type        = number
  default     = 250
}

variable "container_image" {
  description = "Docker image for Mattermost"
  type        = string
  default     = "mattermost/mattermost-team-edition:latest"
}

variable "certificate_arn" {
  description = "ARN of an existing ACM certificate. Required when create_certificate is false."
  type        = string
  default     = null
}

variable "create_certificate" {
  description = "Whether to create a new ACM certificate. Set to false when providing certificate_arn."
  type        = bool
  default     = true
}

variable "enable_open_server" {
  description = "Allow open signup (anyone can create an account)"
  type        = bool
  default     = true
}

variable "subdomain" {
  description = "Subdomain for Mattermost (e.g., 'mm' results in mm.dev.example.com)"
  type        = string
  default     = "mm"
}

# OIDC configuration (for SSO via Zitadel)
variable "oidc_issuer" {
  description = "OIDC issuer URL (e.g., https://auth.dev.example.com)"
  type        = string
  default     = ""
}

variable "oidc_client_id" {
  description = "OIDC client ID"
  type        = string
  default     = ""
}

variable "oidc_client_secret_arn" {
  description = "ARN of the Secrets Manager secret containing OIDC client credentials (JSON with 'client_secret' key)"
  type        = string
  default     = ""
}

# Azure AD (Office 365) OAuth configuration
variable "azure_tenant_id" {
  description = "Azure AD tenant ID (use 'common' for multi-tenant)"
  type        = string
  default     = ""
}

variable "azure_client_id" {
  description = "Azure AD application (client) ID"
  type        = string
  default     = ""
}

variable "azure_client_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Azure AD credentials (JSON with 'client_secret' key)"
  type        = string
  default     = ""
}

# Email configuration (SES)
variable "region" {
  description = "AWS region for SES endpoint"
  type        = string
  default     = "eu-central-1"
}

variable "smtp_from_email" {
  description = "Email address to send from (must be verified in SES). Set to enable email notifications."
  type        = string
  default     = ""
}
