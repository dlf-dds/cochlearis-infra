# Mattermost <-> Outline Bridge Module Outputs

output "bridge_endpoint" {
  description = "Full URL for the bridge endpoint (use for Mattermost slash command and Outline webhook)"
  value       = "https://${local.domain}/bridge"
}

output "bridge_domain" {
  description = "Domain name for the bridge"
  value       = local.domain
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.bridge.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.bridge.arn
}

output "lambda_log_group" {
  description = "CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "api_gateway_id" {
  description = "ID of the API Gateway"
  value       = aws_apigatewayv2_api.bridge.id
}

output "api_gateway_endpoint" {
  description = "Default API Gateway endpoint (before custom domain)"
  value       = aws_apigatewayv2_api.bridge.api_endpoint
}
