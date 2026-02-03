# ECR Module Variables

variable "repositories" {
  description = "Map of repository names to their source images"
  type = map(object({
    source = string # Original Docker Hub image (for reference)
  }))
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
