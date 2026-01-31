locals {
  admin_users = {
    "dedd.flanders" = {
      Name  = "Dedd Flanders"
      Email = "dedd.flanders@gmail.com"
    }
  }

  alumni_users = {
    # Add alumni/former users here (access revoked)
    # "username" = {
    #   Name  = "Full Name"
    #   Email = "email@example.com"
    # }
  }

  project_tags = {
    Project    = var.project
    Automation = "Terraform"
  }
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "cochlearis"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "global"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}
