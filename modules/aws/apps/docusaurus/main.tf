# Docusaurus Documentation Site Module
#
# Static documentation site served via ECS

locals {
  name_prefix = "${var.project}-${var.environment}"
  domain      = "developer.${var.environment}.${var.domain_name}"
}

# SSL Certificate
module "certificate" {
  source = "../../acm-certificate"

  project     = var.project
  environment = var.environment
  domain_name = local.domain
  zone_id     = var.route53_zone_id
}

# Add certificate to ALB
resource "aws_lb_listener_certificate" "main" {
  listener_arn    = var.alb_listener_arn
  certificate_arn = module.certificate.validation_certificate_arn
}

# Route53 record
resource "aws_route53_record" "main" {
  zone_id = var.route53_zone_id
  name    = local.domain
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# Note: ALB -> ECS security group rules are managed centrally in the ECS cluster module
# to avoid duplicate rule conflicts when multiple apps use the same ports.

# ECS Service
module "service" {
  source = "../../ecs-service"

  project     = var.project
  environment = var.environment

  service_name = "docusaurus"
  cluster_id   = var.ecs_cluster_id
  vpc_id       = var.vpc_id

  private_subnet_ids = var.private_subnet_ids
  security_group_ids = [var.ecs_tasks_security_group_id]

  task_execution_role_arn = var.task_execution_role_arn
  task_role_arn           = var.task_role_arn

  container_image = var.container_image
  container_port  = 80

  cpu           = var.ecs_cpu
  memory        = var.ecs_memory
  desired_count = var.desired_count

  environment_variables = {}
  secrets               = {}

  # ALB Integration
  create_alb_target_group = true
  alb_listener_arn        = var.alb_listener_arn
  host_header             = local.domain
  listener_rule_priority  = var.listener_rule_priority
  health_check_path       = "/"
  health_check_matcher    = "200"
}
