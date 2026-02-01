variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "domain_name" {
  description = "Base domain name"
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
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

# ALB
variable "alb_dns_name" {
  description = "ALB DNS name for Route53 alias"
  type        = string
}

variable "alb_zone_id" {
  description = "ALB hosted zone ID for Route53 alias"
  type        = string
}

variable "alb_listener_arn" {
  description = "ALB HTTPS listener ARN"
  type        = string
}

variable "alb_security_group_id" {
  description = "ALB security group ID"
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
  description = "ECS task execution role ARN"
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN"
  type        = string
}

variable "container_image" {
  description = "Container image for Docusaurus"
  type        = string
  default     = "nginx:alpine"
}

variable "ecs_cpu" {
  description = "CPU units for the task"
  type        = number
  default     = 256
}

variable "ecs_memory" {
  description = "Memory (MB) for the task"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of tasks to run"
  type        = number
  default     = 1
}

variable "listener_rule_priority" {
  description = "Priority for ALB listener rule"
  type        = number
  default     = 400
}
