# Mattermost <-> Outline Bridge Module
#
# Serverless bridge using Lambda + API Gateway HTTP API
# Handles bi-directional integration between Mattermost and Outline

locals {
  name_prefix   = "${var.project}-${var.environment}"
  function_name = "${local.name_prefix}-mm-outline-bridge"
  domain        = "bridge.${var.environment}.${var.domain_name}"
  outline_url   = var.outline_base_url != "" ? var.outline_base_url : "https://wiki.${var.environment}.${var.domain_name}"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# IAM Role for Lambda
# =============================================================================

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bridge_lambda" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = merge(var.tags, {
    Name = "${local.function_name}-role"
  })
}

data "aws_iam_policy_document" "bridge_lambda" {
  # CloudWatch Logs
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # Secrets Manager - read secrets
  statement {
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      var.outline_api_key_secret_arn,
      var.mattermost_webhook_secret_arn
    ]
  }
}

resource "aws_iam_role_policy" "bridge_lambda" {
  name   = "${local.function_name}-policy"
  role   = aws_iam_role.bridge_lambda.id
  policy = data.aws_iam_policy_document.bridge_lambda.json
}

# =============================================================================
# Lambda Function
# =============================================================================

data "archive_file" "bridge_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "bridge" {
  function_name = local.function_name
  role          = aws_iam_role.bridge_lambda.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory

  filename         = data.archive_file.bridge_lambda.output_path
  source_code_hash = data.archive_file.bridge_lambda.output_base64sha256

  environment {
    variables = {
      OUTLINE_API_KEY_SECRET_ARN    = var.outline_api_key_secret_arn
      MATTERMOST_WEBHOOK_SECRET_ARN = var.mattermost_webhook_secret_arn
      OUTLINE_BASE_URL              = local.outline_url
      OUTLINE_COLLECTION_ID         = var.outline_collection_id
    }
  }

  tags = merge(var.tags, {
    Name = local.function_name
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${local.function_name}-logs"
  })
}

# =============================================================================
# API Gateway HTTP API
# =============================================================================

resource "aws_apigatewayv2_api" "bridge" {
  name          = "${local.name_prefix}-bridge-api"
  protocol_type = "HTTP"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-bridge-api"
  })
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.bridge.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      errorMessage   = "$context.error.message"
    })
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-bridge-api-stage"
  })
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${local.name_prefix}-bridge"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-bridge-api-logs"
  })
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.bridge.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.bridge.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "bridge" {
  api_id    = aws_apigatewayv2_api.bridge.id
  route_key = "POST /bridge"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bridge.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.bridge.execution_arn}/*/*"
}

# =============================================================================
# Custom Domain with ACM Certificate
# =============================================================================

resource "aws_acm_certificate" "bridge" {
  domain_name       = local.domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-bridge-cert"
  })
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.bridge.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

resource "aws_acm_certificate_validation" "bridge" {
  certificate_arn         = aws_acm_certificate.bridge.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_apigatewayv2_domain_name" "bridge" {
  domain_name = local.domain

  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.bridge.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-bridge-domain"
  })
}

resource "aws_apigatewayv2_api_mapping" "bridge" {
  api_id      = aws_apigatewayv2_api.bridge.id
  domain_name = aws_apigatewayv2_domain_name.bridge.id
  stage       = aws_apigatewayv2_stage.default.id
}

resource "aws_route53_record" "bridge" {
  name    = local.domain
  type    = "A"
  zone_id = var.route53_zone_id

  alias {
    name                   = aws_apigatewayv2_domain_name.bridge.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.bridge.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}
