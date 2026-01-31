# Bootstrap Module - Terraform State Infrastructure
#
# Creates S3 bucket, KMS key, and DynamoDB table for Terraform state management.

data "aws_canonical_user_id" "current_user" {}
data "aws_region" "current" {}

module "s3_kms_key" {
  source  = "dod-iac/s3-kms-key/aws"
  version = "1.0.4"

  name        = format("alias/%s-s3-tf-state", var.iam_account_alias)
  description = format("A KMS key used to encrypt objects at rest in S3 for terraform state for %s.", var.iam_account_alias)
  principals  = ["*"]
}

module "s3_tf_state_logs" {
  source  = "dod-iac/s3-bucket/aws"
  version = "2.0.1"

  grants = [
    {
      id          = data.aws_canonical_user_id.current_user.id
      permissions = ["FULL_CONTROL"]
      type        = "CanonicalUser"
    },
    {
      permissions = ["READ_ACP", "WRITE"]
      type        = "Group",
      uri         = "http://acs.amazonaws.com/groups/s3/LogDelivery"
    }
  ]
  name = format("%s-tf-state-logs-%s", var.iam_account_alias, data.aws_region.current.name)
  server_side_encryption = {
    kms_master_key_id = module.s3_kms_key.aws_kms_key_arn
  }
  versioning_enabled = true
}

module "s3_tf_state" {
  source  = "dod-iac/s3-bucket/aws"
  version = "2.0.1"

  logging = {
    bucket = module.s3_tf_state_logs.id
  }
  name = format("%s-tf-state-%s", var.iam_account_alias, data.aws_region.current.name)
  server_side_encryption = {
    kms_master_key_id = module.s3_kms_key.aws_kms_key_arn
  }
}

resource "aws_dynamodb_table" "tf_state_lock" {
  name           = format("%s-tf-state-lock", var.iam_account_alias)
  hash_key       = "LockID"
  read_capacity  = 2
  write_capacity = 2

  server_side_encryption {
    enabled = true
  }

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}
