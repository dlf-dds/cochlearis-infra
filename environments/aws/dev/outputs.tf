output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = module.vpc.public_subnet_ids
}

output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = module.ecs.cluster_id
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

# ALB
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

# Zitadel
output "zitadel_url" {
  description = "URL for Zitadel identity provider"
  value       = module.zitadel.url
}

output "zitadel_db_endpoint" {
  description = "Endpoint for Zitadel PostgreSQL database"
  value       = module.zitadel.db_endpoint
}

# Zulip (EC2)
output "zulip_url" {
  description = "URL for Zulip chat"
  value       = module.zulip_ec2.url
}

output "zulip_instance_id" {
  description = "EC2 instance ID for Zulip"
  value       = module.zulip_ec2.instance_id
}

output "zulip_secrets_arn" {
  description = "ARN of Secrets Manager secret containing Zulip credentials"
  value       = module.zulip_ec2.secrets_arn
}

# BookStack
output "bookstack_url" {
  description = "URL for BookStack documentation"
  value       = module.bookstack.url
}

output "bookstack_db_endpoint" {
  description = "Endpoint for BookStack MySQL database"
  value       = module.bookstack.db_endpoint
}

# Mattermost
output "mattermost_url" {
  description = "URL for Mattermost chat"
  value       = module.mattermost.url
}

output "mattermost_db_endpoint" {
  description = "Endpoint for Mattermost PostgreSQL database"
  value       = module.mattermost.db_endpoint
}

# Governance
output "governance_sns_topic_arn" {
  description = "ARN of the governance alerts SNS topic"
  value       = module.governance.sns_topic_arn
}

output "governance_lambda_function_name" {
  description = "Name of the lifecycle manager Lambda"
  value       = module.governance.lambda_function_name
}
