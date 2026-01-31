# SES SMTP User Module
#
# Creates an IAM user with SES SendRawEmail permissions for SMTP access.

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_user" "main" {
  name = var.name
  tags = var.tags
}

data "aws_iam_policy_document" "main" {
  statement {
    sid = "AmazonSesSendingAccess"
    actions = [
      "ses:SendRawEmail"
    ]
    effect    = "Allow"
    resources = ["*"]
  }
}

resource "aws_iam_policy" "main" {
  name        = format("%s-policy", var.name)
  description = format("The policy for %s.", var.name)
  policy      = data.aws_iam_policy_document.main.json
}

resource "aws_iam_user_policy_attachment" "main" {
  user       = aws_iam_user.main.name
  policy_arn = aws_iam_policy.main.arn
}
