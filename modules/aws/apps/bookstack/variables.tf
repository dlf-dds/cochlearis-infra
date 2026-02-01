# BookStack App Module Variables

variable "project" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
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

variable "task_role_name" {
  description = "Name of the ECS task role"
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
  default     = 300
}

variable "container_image" {
  description = "Docker image for BookStack"
  type        = string
  default     = "lscr.io/linuxserver/bookstack:latest"
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
