variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "domain_name" {
  description = "Base domain name (e.g., almondbread.org)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block (for LOADBALANCER_IPS)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "alb_listener_arn" {
  description = "ALB HTTPS listener ARN"
  type        = string
}

variable "alb_dns_name" {
  description = "ALB DNS name"
  type        = string
}

variable "alb_zone_id" {
  description = "ALB Route53 zone ID"
  type        = string
}

variable "ecs_cluster_id" {
  description = "ECS cluster ID"
  type        = string
}

variable "ecs_tasks_security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "task_execution_role_arn" {
  description = "Task execution role ARN"
  type        = string
}

variable "task_execution_role_name" {
  description = "Task execution role name"
  type        = string
}

variable "task_role_arn" {
  description = "Task role ARN"
  type        = string
}

variable "task_role_name" {
  description = "Task role name"
  type        = string
}

variable "admin_email" {
  description = "Administrator email"
  type        = string
}

variable "container_image" {
  description = "Docker image for Zulip"
  type        = string
  default     = "zulip/docker-zulip:9.4-0"
}

variable "ecs_cpu" {
  description = "CPU units (all-in-one needs more resources)"
  type        = number
  default     = 2048
}

variable "ecs_memory" {
  description = "Memory in MB (all-in-one needs more resources)"
  type        = number
  default     = 4096
}

variable "desired_count" {
  description = "Desired task count"
  type        = number
  default     = 1
}

variable "listener_rule_priority" {
  description = "ALB listener rule priority"
  type        = number
  default     = 115
}

# Google OAuth
variable "google_client_id" {
  description = "Google OAuth client ID"
  type        = string
  default     = ""
}

variable "google_client_secret_arn" {
  description = "Google OAuth client secret ARN in Secrets Manager"
  type        = string
  default     = ""
}

# Azure AD OAuth
variable "azure_tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
  default     = ""
}

variable "azure_client_id" {
  description = "Azure AD client ID"
  type        = string
  default     = ""
}

variable "azure_client_secret_arn" {
  description = "Azure AD client secret ARN in Secrets Manager"
  type        = string
  default     = ""
}
