# EFS Module Variables

variable "project" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "name" {
  description = "Name identifier for the EFS filesystem"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for mount targets"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to access EFS"
  type        = list(string)
}

variable "performance_mode" {
  description = "EFS performance mode (generalPurpose or maxIO)"
  type        = string
  default     = "generalPurpose"
}

variable "throughput_mode" {
  description = "EFS throughput mode (bursting, provisioned, or elastic)"
  type        = string
  default     = "bursting"
}

variable "provisioned_throughput_in_mibps" {
  description = "Provisioned throughput in MiB/s (only used if throughput_mode is provisioned)"
  type        = number
  default     = null
}

variable "transition_to_ia" {
  description = "Lifecycle policy for transitioning to Infrequent Access"
  type        = string
  default     = "AFTER_30_DAYS"
}

variable "posix_user_uid" {
  description = "POSIX user ID for the access point"
  type        = number
  default     = 1000
}

variable "posix_user_gid" {
  description = "POSIX group ID for the access point"
  type        = number
  default     = 1000
}

variable "root_directory_path" {
  description = "Path for the access point root directory"
  type        = string
  default     = "/data"
}

variable "root_directory_permissions" {
  description = "Permissions for the root directory"
  type        = string
  default     = "755"
}
