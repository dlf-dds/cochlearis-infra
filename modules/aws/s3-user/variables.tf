variable "name" {
  type        = string
  description = "The name of the AWS IAM user."
}

variable "bucket_name" {
  type        = string
  description = "The S3 bucket name to scope access to. Required for least-privilege access."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the AWS IAM user."
  default     = {}
}
