# IAM Users
# Users are defined in variables.tf under admin_users and alumni_users

resource "aws_iam_user" "user" {
  for_each = merge(local.admin_users, local.alumni_users)

  name = each.key

  tags = merge(each.value, local.project_tags)
}

resource "aws_iam_user_group_membership" "user" {
  for_each = merge(local.admin_users, local.alumni_users)

  user = aws_iam_user.user[each.key].name

  groups = sort(flatten([
    contains(keys(local.admin_users), each.key) ? [aws_iam_group.admin.name] : [],
    contains(keys(local.alumni_users), each.key) ? [aws_iam_group.alumni.name] : [],
  ]))
}
