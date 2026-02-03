# Zulip EC2 Variables

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
  description = "Base domain name (e.g., almondbread.org)"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS records"
  type        = string
}

# Network
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block (used for loadbalancer trust configuration)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_id" {
  description = "Private subnet ID for EC2 instance"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID (for NAT gateway egress)"
  type        = string
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

# EC2 Configuration
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium" # 2 vCPU, 4GB RAM
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 50
}

variable "listener_rule_priority" {
  description = "Priority for the ALB listener rule"
  type        = number
  default     = 200
}

# Application Configuration
variable "admin_email" {
  description = "Administrator email for Zulip"
  type        = string
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
  description = "ARN of the Secrets Manager secret containing Azure client secret"
  type        = string
  default     = ""
}

# Google OAuth
variable "google_client_id" {
  description = "Google OAuth client ID"
  type        = string
  default     = ""
}

variable "google_client_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Google client secret"
  type        = string
  default     = ""
}

# Email configuration (SES)
variable "smtp_from_email" {
  description = "From email address for outgoing emails. Set to enable email via SES."
  type        = string
  default     = ""
}

variable "smtp_from_name" {
  description = "From name for outgoing emails"
  type        = string
  default     = "Zulip"
}
