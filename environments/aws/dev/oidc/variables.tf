variable "project" {
  description = "Project name"
  type        = string
  default     = "cochlearis"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "domain_name" {
  description = "Base domain name"
  type        = string
  default     = "almondbread.org"
}
