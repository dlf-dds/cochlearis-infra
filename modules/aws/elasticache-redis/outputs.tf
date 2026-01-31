output "cluster_id" {
  description = "The ID of the ElastiCache cluster"
  value       = aws_elasticache_cluster.main.id
}

output "endpoint" {
  description = "The endpoint of the Redis cluster"
  value       = aws_elasticache_cluster.main.cache_nodes[0].address
}

output "port" {
  description = "The port of the Redis cluster"
  value       = aws_elasticache_cluster.main.port
}

output "security_group_id" {
  description = "The ID of the Redis security group"
  value       = aws_security_group.redis.id
}

output "connection_string" {
  description = "Redis connection string (host:port)"
  value       = "${aws_elasticache_cluster.main.cache_nodes[0].address}:${aws_elasticache_cluster.main.port}"
}
