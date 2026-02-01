variable "project" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the ECS cluster will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}

variable "capacity_providers" {
  description = "List of capacity providers to associate with the cluster"
  type        = list(string)
  default     = ["FARGATE", "FARGATE_SPOT"]
}

variable "default_capacity_provider_strategy" {
  description = "Default capacity provider strategy"
  type = list(object({
    capacity_provider = string
    weight            = number
    base              = optional(number)
  }))
  default = [
    {
      capacity_provider = "FARGATE"
      weight            = 1
      base              = 1
    },
    {
      capacity_provider = "FARGATE_SPOT"
      weight            = 4
    }
  ]
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "enable_service_discovery" {
  description = "Enable AWS Cloud Map service discovery"
  type        = bool
  default     = true
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB for ingress rules"
  type        = string
}

variable "alb_ingress_ports" {
  description = "List of ports to allow ingress from ALB to ECS tasks. Leave empty to disable rules."
  type        = list(number)
  default     = []
}

variable "internal_alb_security_group_id" {
  description = "Security group ID of the internal ALB for ingress rules"
  type        = string
  default     = ""
}

variable "internal_alb_ingress_ports" {
  description = "List of ports to allow ingress from internal ALB to ECS tasks. Leave empty to disable rules."
  type        = list(number)
  default     = []
}
