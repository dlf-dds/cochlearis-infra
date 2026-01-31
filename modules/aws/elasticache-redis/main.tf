# ElastiCache Redis Module
#
# Creates a Redis cluster for caching and session storage.

locals {
  name_prefix = "${var.project}-${var.environment}"
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.name_prefix}-${var.identifier}-redis-subnet"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${local.name_prefix}-${var.identifier}-redis-subnet"
  }
}

resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-${var.identifier}-redis-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name_prefix}-${var.identifier}-redis-sg"
  }
}

resource "aws_security_group_rule" "redis_ingress" {
  count = length(var.allowed_security_group_ids)

  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = var.allowed_security_group_ids[count.index]
  security_group_id        = aws_security_group.redis.id
  description              = "Allow Redis from allowed security groups"
}

resource "aws_security_group_rule" "redis_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.redis.id
  description       = "Allow all outbound traffic"
}

resource "aws_elasticache_cluster" "main" {
  cluster_id           = "${local.name_prefix}-${var.identifier}"
  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  num_cache_nodes      = 1
  parameter_group_name = var.parameter_group_name
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = var.snapshot_window
  maintenance_window       = var.maintenance_window

  auto_minor_version_upgrade = true

  tags = {
    Name = "${local.name_prefix}-${var.identifier}"
  }
}
