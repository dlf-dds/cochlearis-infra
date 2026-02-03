# ECR Module Outputs

output "repository_urls" {
  description = "Map of repository names to their ECR URLs"
  value = {
    for name, repo in aws_ecr_repository.main : name => repo.repository_url
  }
}

output "repository_arns" {
  description = "Map of repository names to their ARNs"
  value = {
    for name, repo in aws_ecr_repository.main : name => repo.arn
  }
}
