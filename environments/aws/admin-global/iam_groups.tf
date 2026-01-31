# IAM Groups

resource "aws_iam_group" "admin" {
  name = "Administrators"
}

resource "aws_iam_group_policy_attachment" "admin_administrator" {
  group      = aws_iam_group.admin.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_group" "alumni" {
  name = "alumni"
}

# Alumni group has no policies - access is revoked
