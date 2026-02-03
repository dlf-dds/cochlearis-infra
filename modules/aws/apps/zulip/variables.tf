# Zulip App Module Variables

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

# Redis configuration
variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

# ECS configuration (includes resources for PostgreSQL sidecar)
variable "ecs_cpu" {
  description = "CPU units for the ECS task (Zulip + PostgreSQL sidecar)"
  type        = number
  default     = 2048
}

variable "ecs_memory" {
  description = "Memory in MB for the ECS task (Zulip + PostgreSQL sidecar)"
  type        = number
  default     = 4096
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 1
}

variable "listener_rule_priority" {
  description = "Priority for the ALB listener rule"
  type        = number
  default     = 200
}

variable "container_image" {
  description = "Docker image for Zulip"
  type        = string
  default     = "zulip/docker-zulip:latest"
}

variable "postgres_image" {
  description = "Docker image for PostgreSQL sidecar"
  type        = string
  default     = "zulip/zulip-postgresql:14"
}

variable "admin_email" {
  description = "Administrator email address"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for LOADBALANCER_IPS configuration"
  type        = string
  default     = "10.0.0.0/16"
}

# OIDC configuration (for SSO via Zitadel) - ABANDONED, see OIDC.md
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

# Google OAuth configuration (preferred SSO method)
variable "google_client_id" {
  description = "Google OAuth client ID"
  type        = string
  default     = ""
}

variable "google_client_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Google OAuth credentials (JSON with 'client_secret' key)"
  type        = string
  default     = ""
}

# Azure AD OAuth configuration
variable "azure_tenant_id" {
  description = "Azure AD tenant ID"
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
