variable "project" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "cochlearis"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "staging"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}
