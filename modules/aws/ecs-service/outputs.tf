output "service_id" {
  description = "The ID of the ECS service"
  value       = aws_ecs_service.main.id
}

output "service_name" {
  description = "The name of the ECS service"
  value       = aws_ecs_service.main.name
}

output "service_arn" {
  description = "The ARN of the ECS service"
  value       = aws_ecs_service.main.id
}

output "task_definition_arn" {
  description = "The ARN of the task definition"
  value       = aws_ecs_task_definition.main.arn
}

output "task_definition_family" {
  description = "The family of the task definition"
  value       = aws_ecs_task_definition.main.family
}

output "target_group_arn" {
  description = "The ARN of the ALB target group"
  value       = var.create_alb_target_group ? aws_lb_target_group.main[0].arn : null
}

output "log_group_name" {
  description = "The name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.service.name
}

output "log_group_arn" {
  description = "The ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.service.arn
}
