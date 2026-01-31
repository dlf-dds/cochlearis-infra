variable "name" {
  type        = string
  description = "The name of the AWS IAM user."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the AWS IAM user."
  default     = {}
}
