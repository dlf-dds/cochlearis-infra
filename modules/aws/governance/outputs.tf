output "sns_topic_arn" {
  description = "ARN of the governance alerts SNS topic"
  value       = aws_sns_topic.governance_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the governance alerts SNS topic"
  value       = aws_sns_topic.governance_alerts.name
}

output "lambda_function_arn" {
  description = "ARN of the lifecycle manager Lambda function"
  value       = aws_lambda_function.lifecycle_manager.arn
}

output "lambda_function_name" {
  description = "Name of the lifecycle manager Lambda function"
  value       = aws_lambda_function.lifecycle_manager.function_name
}

output "eventbridge_rule_arn" {
  description = "ARN of the weekly governance EventBridge rule"
  value       = aws_cloudwatch_event_rule.weekly_governance.arn
}

output "budget_name" {
  description = "Name of the monthly budget"
  value       = aws_budgets_budget.monthly.name
}

output "governance_tags" {
  description = "Standard governance tags to apply to all resources"
  value = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner_email
    ManagedBy   = "terraform"
    Lifecycle   = "persistent" # Default, can be overridden
  }
}
