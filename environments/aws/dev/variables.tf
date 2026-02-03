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

# Zitadel OIDC integration (ABANDONED - see OIDC.md)
variable "enable_zitadel_oidc" {
  description = "Enable Zitadel OIDC integration for SSO (ABANDONED after 48 hours - use Google OAuth instead)"
  type        = bool
  default     = false
}

# Google OAuth integration (preferred SSO method)
variable "enable_google_oauth" {
  description = "Enable Google OAuth for BookStack and Zulip"
  type        = bool
  default     = false
}

variable "google_oauth_client_id" {
  description = "Google OAuth client ID (from Google Cloud Console)"
  type        = string
  default     = ""
}

variable "google_oauth_secret_arn" {
  description = "ARN of Secrets Manager secret containing Google OAuth credentials (JSON with 'client_secret' key)"
  type        = string
  default     = ""
}

# Azure AD OAuth integration
variable "enable_azure_oauth" {
  description = "Enable Azure AD OAuth for all services"
  type        = bool
  default     = false
}

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
  description = "ARN of Secrets Manager secret containing Azure AD credentials (JSON with 'client_secret' key)"
  type        = string
  default     = ""
}

# Outline Slack OAuth (works with any Slack workspace including free/personal)
variable "outline_slack_client_id" {
  description = "Slack OAuth client ID for Outline (create at https://api.slack.com/apps)"
  type        = string
  default     = ""
}

variable "outline_slack_secret_arn" {
  description = "ARN of Secrets Manager secret containing Slack OAuth credentials (JSON with 'client_secret' key)"
  type        = string
  default     = ""
}

# Docusaurus ALB OIDC Authentication
variable "enable_docusaurus_auth" {
  description = "Enable ALB-level OIDC authentication for Docusaurus (uses Azure AD if configured, else Google OAuth)"
  type        = bool
  default     = false
}
