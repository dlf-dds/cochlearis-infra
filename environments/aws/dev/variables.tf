variable "project" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "cochlearis"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "domain_name" {
  description = "Root domain name for services"
  type        = string
  default     = "almondbread.org"
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the domain"
  type        = string
}
