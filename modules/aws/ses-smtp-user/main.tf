# SES SMTP User Module
#
# Creates an IAM user with SES SendRawEmail permissions for SMTP access.
# Also creates access keys and stores SMTP credentials in Secrets Manager.

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

# Create access key for SMTP authentication
resource "aws_iam_access_key" "main" {
  user = aws_iam_user.main.name
}

# Store SMTP credentials in Secrets Manager
# Note: The SMTP password is derived from the secret access key using AWS's algorithm
# For SES SMTP, the username is the access key ID, and the password is derived from the secret
resource "aws_secretsmanager_secret" "smtp_credentials" {
  name        = "${var.name}-smtp-credentials"
  description = "SMTP credentials for ${var.name}"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "smtp_credentials" {
  secret_id = aws_secretsmanager_secret.smtp_credentials.id
  secret_string = jsonencode({
    username = aws_iam_access_key.main.id
    password = aws_iam_access_key.main.ses_smtp_password_v4
  })
}
