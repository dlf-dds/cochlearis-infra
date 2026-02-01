# Governance Module Variables

variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "owner_email" {
  description = "Infrastructure owner email for alerts"
  type        = string
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD"
  type        = number
  default     = 200
}

variable "lifecycle_warning_days" {
  description = "Days before expiry to start sending warnings"
  type        = number
  default     = 30
}

variable "lifecycle_termination_days" {
  description = "Days after creation to terminate temporary resources"
  type        = number
  default     = 60
}

variable "enable_auto_termination" {
  description = "Enable automatic termination of expired resources"
  type        = bool
  default     = false
}

variable "cost_alert_thresholds" {
  description = "Budget thresholds for cost alerts (percentages)"
  type        = list(number)
  default     = [50, 80, 100, 120]
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
