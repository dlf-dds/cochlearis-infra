variable "project" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "service_name" {
  description = "Name of the ECS service"
  type        = string
}

variable "cluster_id" {
  description = "ECS cluster ID"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the target group"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the ECS tasks"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for the ECS tasks"
  type        = list(string)
}

variable "task_execution_role_arn" {
  description = "ARN of the task execution role"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the task role"
  type        = string
}

variable "container_image" {
  description = "Docker image for the container"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
}

variable "cpu" {
  description = "CPU units for the task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memory in MB for the task"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 1
}

variable "environment_variables" {
  description = "Environment variables for the container"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secrets from Secrets Manager or SSM Parameter Store (key = env var name, value = ARN)"
  type        = map(string)
  default     = {}
}

variable "health_check" {
  description = "Container health check configuration"
  type = object({
    command      = list(string)
    interval     = number
    timeout      = number
    retries      = number
    start_period = number
  })
  default = null
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# ALB Integration
variable "create_alb_target_group" {
  description = "Create an ALB target group for this service"
  type        = bool
  default     = true
}

variable "alb_listener_arn" {
  description = "ARN of the ALB HTTPS listener"
  type        = string
  default     = null
}

variable "host_header" {
  description = "Host header for ALB listener rule routing"
  type        = string
  default     = null
}

variable "listener_rule_priority" {
  description = "Priority for the ALB listener rule"
  type        = number
  default     = 100
}

variable "health_check_path" {
  description = "Health check path for the target group"
  type        = string
  default     = "/"
}

variable "health_check_matcher" {
  description = "HTTP status codes for healthy response"
  type        = string
  default     = "200-399"
}

variable "target_group_protocol_version" {
  description = "Protocol version for the target group (HTTP1, HTTP2, or GRPC). HTTP2 required for gRPC services."
  type        = string
  default     = "HTTP1"
}

variable "container_command" {
  description = "Command to run in the container (overrides image CMD)"
  type        = list(string)
  default     = null
}

# EFS Volume Support
variable "efs_volumes" {
  description = "EFS volumes to mount in the container"
  type = list(object({
    name            = string
    file_system_id  = string
    access_point_id = string
    container_path  = string
    read_only       = optional(bool, false)
  }))
  default = []
}

# Sidecar containers
variable "sidecar_containers" {
  description = "Additional sidecar containers to run alongside the main container"
  type = list(object({
    name                  = string
    image                 = string
    essential             = optional(bool, true)
    port                  = optional(number)
    user                  = optional(string) # User to run the container as (e.g., "999:999")
    environment_variables = optional(map(string), {})
    secrets               = optional(map(string), {})
    command               = optional(list(string))
    health_check = optional(object({
      command      = list(string)
      interval     = number
      timeout      = number
      retries      = number
      start_period = number
    }))
    mount_points = optional(list(object({
      volume_name    = string
      container_path = string
      read_only      = optional(bool, false)
    })), [])
    depends_on = optional(list(object({
      container_name = string
      condition      = string # START, COMPLETE, SUCCESS, HEALTHY
    })), [])
  }))
  default = []
}
