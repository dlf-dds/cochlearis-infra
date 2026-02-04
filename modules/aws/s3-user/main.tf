# S3 User Module
#
# Creates an IAM user with scoped S3 access permissions.
# SECURITY: Access is restricted to a specific bucket (least privilege).

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_user" "main" {
  name = var.name
  tags = var.tags
}

data "aws_iam_policy_document" "main" {
  statement {
    sid = "AllowS3BucketAccess"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetObjectAcl",
      "s3:PutObjectAcl"
    ]
    effect = "Allow"
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${var.bucket_name}",
      "arn:${data.aws_partition.current.partition}:s3:::${var.bucket_name}/*"
    ]
  }
}

resource "aws_iam_policy" "main" {
  name        = format("%s-policy", var.name)
  description = format("Scoped S3 access policy for %s (bucket: %s)", var.name, var.bucket_name)
  policy      = data.aws_iam_policy_document.main.json
}

resource "aws_iam_user_policy_attachment" "main" {
  user       = aws_iam_user.main.name
  policy_arn = aws_iam_policy.main.arn
}
