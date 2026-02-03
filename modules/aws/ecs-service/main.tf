# ECS Service Module
#
# Creates an ECS service with task definition, ALB integration, and auto-scaling.

locals {
  name_prefix = "${var.project}-${var.environment}"
}

resource "aws_cloudwatch_log_group" "service" {
  name              = "/ecs/${local.name_prefix}/${var.service_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.name_prefix}-${var.service_name}-logs"
  }
}

resource "aws_ecs_task_definition" "main" {
  family                   = "${local.name_prefix}-${var.service_name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode(concat(
    # Main container
    [
      merge(
        {
          name      = var.service_name
          image     = var.container_image
          essential = true

          portMappings = [
            {
              containerPort = var.container_port
              hostPort      = var.container_port
              protocol      = "tcp"
            }
          ]

          environment = [
            for key, value in var.environment_variables : {
              name  = key
              value = value
            }
          ]

          secrets = [
            for key, value in var.secrets : {
              name      = key
              valueFrom = value
            }
          ]

          logConfiguration = {
            logDriver = "awslogs"
            options = {
              "awslogs-group"         = aws_cloudwatch_log_group.service.name
              "awslogs-region"        = data.aws_region.current.name
              "awslogs-stream-prefix" = "ecs"
            }
          }

          healthCheck = var.health_check != null ? {
            command     = var.health_check.command
            interval    = var.health_check.interval
            timeout     = var.health_check.timeout
            retries     = var.health_check.retries
            startPeriod = var.health_check.start_period
          } : null

          mountPoints = [
            for vol in var.efs_volumes : {
              sourceVolume  = vol.name
              containerPath = vol.container_path
              readOnly      = vol.read_only
            }
          ]

          # Add dependsOn if there are sidecar containers that need to start first
          dependsOn = length(var.sidecar_containers) > 0 ? [
            for sc in var.sidecar_containers : {
              containerName = sc.name
              condition     = sc.health_check != null ? "HEALTHY" : "START"
            } if sc.essential
          ] : null
        },
        var.container_command != null ? { command = var.container_command } : {}
      )
    ],
    # Sidecar containers
    [
      for sc in var.sidecar_containers : merge(
        {
          name      = sc.name
          image     = sc.image
          essential = sc.essential

          portMappings = sc.port != null ? [
            {
              containerPort = sc.port
              hostPort      = sc.port
              protocol      = "tcp"
            }
          ] : []

          environment = [
            for key, value in sc.environment_variables : {
              name  = key
              value = value
            }
          ]

          secrets = [
            for key, value in sc.secrets : {
              name      = key
              valueFrom = value
            }
          ]

          logConfiguration = {
            logDriver = "awslogs"
            options = {
              "awslogs-group"         = aws_cloudwatch_log_group.service.name
              "awslogs-region"        = data.aws_region.current.name
              "awslogs-stream-prefix" = "ecs-${sc.name}"
            }
          }

          healthCheck = sc.health_check != null ? {
            command     = sc.health_check.command
            interval    = sc.health_check.interval
            timeout     = sc.health_check.timeout
            retries     = sc.health_check.retries
            startPeriod = sc.health_check.start_period
          } : null

          mountPoints = [
            for mp in sc.mount_points : {
              sourceVolume  = mp.volume_name
              containerPath = mp.container_path
              readOnly      = mp.read_only
            }
          ]

          dependsOn = length(sc.depends_on) > 0 ? [
            for dep in sc.depends_on : {
              containerName = dep.container_name
              condition     = dep.condition
            }
          ] : null
        },
        sc.command != null ? { command = sc.command } : {},
        sc.user != null ? { user = sc.user } : {}
      )
    ]
  ))

  # EFS volume definitions
  dynamic "volume" {
    for_each = var.efs_volumes
    content {
      name = volume.value.name

      efs_volume_configuration {
        file_system_id     = volume.value.file_system_id
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = volume.value.access_point_id
          iam             = "ENABLED"
        }
      }
    }
  }

  tags = {
    Name = "${local.name_prefix}-${var.service_name}"
  }
}

resource "aws_lb_target_group" "main" {
  count = var.create_alb_target_group ? 1 : 0

  name             = "${local.name_prefix}-${var.service_name}"
  port             = var.container_port
  protocol         = "HTTP"
  protocol_version = var.target_group_protocol_version
  vpc_id           = var.vpc_id
  target_type      = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = var.health_check_matcher
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${local.name_prefix}-${var.service_name}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Listener rule without OIDC authentication
resource "aws_lb_listener_rule" "main" {
  count = var.create_alb_target_group && !var.enable_alb_oidc_auth ? 1 : 0

  listener_arn = var.alb_listener_arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main[0].arn
  }

  condition {
    host_header {
      values = [var.host_header]
    }
  }

  tags = {
    Name = "${local.name_prefix}-${var.service_name}"
  }
}

# Listener rule with ALB OIDC authentication (for static sites like Docusaurus)
resource "aws_lb_listener_rule" "oidc" {
  count = var.create_alb_target_group && var.enable_alb_oidc_auth ? 1 : 0

  listener_arn = var.alb_listener_arn
  priority     = var.listener_rule_priority

  # OIDC authentication action (must be first)
  action {
    type = "authenticate-oidc"
    order = 1

    authenticate_oidc {
      authorization_endpoint = var.alb_oidc_config.authorization_endpoint
      client_id              = var.alb_oidc_config.client_id
      client_secret          = var.alb_oidc_config.client_secret
      issuer                 = var.alb_oidc_config.issuer
      token_endpoint         = var.alb_oidc_config.token_endpoint
      user_info_endpoint     = var.alb_oidc_config.user_info_endpoint
      scope                  = var.alb_oidc_config.scope
      session_timeout        = var.alb_oidc_config.session_timeout

      on_unauthenticated_request = "authenticate"
    }
  }

  # Forward to target group (after authentication)
  action {
    type             = "forward"
    order            = 2
    target_group_arn = aws_lb_target_group.main[0].arn
  }

  condition {
    host_header {
      values = [var.host_header]
    }
  }

  tags = {
    Name = "${local.name_prefix}-${var.service_name}-oidc"
  }
}

resource "aws_ecs_service" "main" {
  name             = var.service_name
  cluster          = var.cluster_id
  task_definition  = aws_ecs_task_definition.main.arn
  desired_count    = var.desired_count
  launch_type      = "FARGATE"
  platform_version = length(var.efs_volumes) > 0 ? "1.4.0" : "LATEST"

  enable_execute_command = var.enable_execute_command

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  # Primary target group (created by this module)
  dynamic "load_balancer" {
    for_each = var.create_alb_target_group ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.main[0].arn
      container_name   = var.service_name
      container_port   = var.container_port
    }
  }

  # Additional target groups (e.g., internal ALB)
  dynamic "load_balancer" {
    for_each = var.additional_target_group_arns
    content {
      target_group_arn = load_balancer.value
      container_name   = var.service_name
      container_port   = var.container_port
    }
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = {
    Name = "${local.name_prefix}-${var.service_name}"
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}

data "aws_region" "current" {}
