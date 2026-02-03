# ECR Repository Module
#
# Creates ECR repositories with lifecycle policies and scanning.
# Used to mirror Docker Hub images and avoid rate limits.

resource "aws_ecr_repository" "main" {
  for_each = var.repositories

  name                 = each.key
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.tags, {
    Name        = each.key
    SourceImage = each.value.source
  })
}

# Lifecycle policy to keep costs down
resource "aws_ecr_lifecycle_policy" "main" {
  for_each = var.repositories

  repository = aws_ecr_repository.main[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
