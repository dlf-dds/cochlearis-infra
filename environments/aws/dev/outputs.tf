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
  value       = "https://${local.zitadel_domain}"
}

output "zitadel_db_endpoint" {
  description = "Endpoint for Zitadel PostgreSQL database"
  value       = module.zitadel_db.endpoint
}

# Zulip
output "zulip_url" {
  description = "URL for Zulip chat"
  value       = "https://${local.zulip_domain}"
}

output "zulip_db_endpoint" {
  description = "Endpoint for Zulip PostgreSQL database"
  value       = module.zulip_db.endpoint
}

output "zulip_redis_endpoint" {
  description = "Endpoint for Zulip Redis cache"
  value       = module.zulip_redis.endpoint
}
