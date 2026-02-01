# Zitadel OIDC Module Variables

variable "organization_id" {
  description = "Zitadel organization ID"
  type        = string
}

variable "project_name" {
  description = "Name of the Zitadel project to create"
  type        = string
  default     = "Cochlearis"
}

variable "secret_prefix" {
  description = "Prefix for Secrets Manager secret names"
  type        = string
}

variable "bookstack_domain" {
  description = "BookStack domain (e.g., docs.dev.example.com)"
  type        = string
}

variable "zulip_domain" {
  description = "Zulip domain (e.g., chat.dev.example.com)"
  type        = string
}

variable "mattermost_domain" {
  description = "Mattermost domain (e.g., mm.dev.example.com)"
  type        = string
}

variable "outline_domain" {
  description = "Outline domain (e.g., wiki.dev.example.com)"
  type        = string
  default     = ""
}
