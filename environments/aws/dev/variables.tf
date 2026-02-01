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

variable "owner_email" {
  description = "Infrastructure owner email for alerts and governance"
  type        = string
  default     = "dedd.flanders@gmail.com"
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD for cost alerts"
  type        = number
  default     = 200
}

variable "enable_auto_termination" {
  description = "Enable automatic termination of expired resources"
  type        = bool
  default     = true
}

# Zitadel OIDC integration
variable "enable_zitadel_oidc" {
  description = "Enable Zitadel OIDC integration for SSO (requires bootstrap script to be run first)"
  type        = bool
  default     = false
}
