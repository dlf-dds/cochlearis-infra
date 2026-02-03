# Mattermost ↔ Outline Bridge: One-Shot Implementation Plan

This document describes the architecture and implementation plan for a bi-directional serverless bridge between Mattermost and Outline.

## Overview

The bridge enables:
1. **OUTBOUND**: Mattermost `/outline` slash command → Create Outline document
2. **INBOUND**: Outline webhook → Notify Mattermost channel

## Architecture

```
┌─────────────────┐         ┌──────────────────────────┐         ┌─────────────────┐
│   Mattermost    │         │     AWS Infrastructure    │         │     Outline     │
│                 │         │                          │         │                 │
│  /outline cmd   │────────▶│  API Gateway HTTP API    │         │                 │
│                 │         │         │                │         │                 │
│                 │         │         ▼                │         │                 │
│                 │         │  Lambda Function         │────────▶│  Create Doc     │
│                 │         │  (Python 3.11)           │         │  (API)          │
│                 │         │         │                │         │                 │
│                 │         │         ▼                │         │                 │
│  Webhook        │◀────────│  Secrets Manager         │◀────────│  Webhook        │
│  (notification) │         │  (API keys, URLs)        │         │  (doc events)   │
└─────────────────┘         └──────────────────────────┘         └─────────────────┘
```

## Request Routing

The Lambda function routes requests based on Content-Type header:

| Content-Type | Source | Handler |
|--------------|--------|---------|
| `application/x-www-form-urlencoded` | Mattermost slash command | `handle_slash_command()` |
| `application/json` | Outline webhook | `handle_outline_webhook()` |

## AWS Resources

### Lambda Function
- **Runtime**: Python 3.11
- **Handler**: `index.handler`
- **Memory**: 128 MB
- **Timeout**: 30 seconds
- **Environment Variables**:
  - `OUTLINE_API_KEY_SECRET_ARN` - Secrets Manager ARN for Outline API key
  - `MATTERMOST_WEBHOOK_SECRET_ARN` - Secrets Manager ARN for Mattermost webhook URL
  - `OUTLINE_BASE_URL` - Outline base URL (e.g., `https://wiki.dev.almondbread.org`)
  - `OUTLINE_COLLECTION_ID` - Default collection ID for new documents

### API Gateway
- **Type**: HTTP API (v2)
- **Route**: `POST /bridge`
- **Custom Domain**: `bridge.dev.almondbread.org`
- **TLS**: ACM certificate with DNS validation

### IAM Permissions
- `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` - CloudWatch Logs
- `secretsmanager:GetSecretValue` - Read secrets for API keys/webhooks

### Secrets Manager
Two secrets store sensitive credentials:

1. **`cochlearis-dev-outline-api-key`**
   ```json
   {"api_key": "ol_..."}
   ```

2. **`cochlearis-dev-mattermost-webhook`**
   ```json
   {"webhook_url": "https://mm.dev.almondbread.org/hooks/..."}
   ```

## File Structure

```
modules/aws/integrations/bridge/
├── main.tf           # Lambda, API Gateway, ACM, Route53
├── variables.tf      # Input variables
├── outputs.tf        # Module outputs
└── lambda/
    └── index.py      # Lambda handler code
```

## Terraform Module Usage

```hcl
module "bridge" {
  count  = var.enable_mm_outline_bridge ? 1 : 0
  source = "../../../modules/aws/integrations/bridge"

  project         = var.project
  environment     = var.environment
  domain_name     = var.domain_name
  route53_zone_id = data.aws_route53_zone.main.zone_id

  outline_api_key_secret_arn    = var.outline_api_key_secret_arn
  outline_collection_id         = var.outline_default_collection_id
  mattermost_webhook_secret_arn = var.mattermost_webhook_secret_arn

  tags = local.common_tags
}
```

## Slash Command Syntax

```
/outline create "Document Title" "Document content in markdown format"
```

Example:
```
/outline create "Sprint 42 Retro" "## What went well\n- Shipped feature X\n\n## Improvements\n- More testing"
```

## Webhook Events

The bridge handles these Outline webhook events:

| Event | Action |
|-------|--------|
| `documents.publish` | Notify "Document published: [Title](url)" |
| `documents.update` | Notify "Document updated: [Title](url)" |
| `documents.delete` | Notify "Document deleted: [Title](url)" |
| `documents.archive` | Notify "Document archived: [Title](url)" |

## Security Considerations

1. **Secrets**: API keys and webhook URLs stored in AWS Secrets Manager, not environment variables
2. **TLS**: All traffic encrypted via HTTPS
3. **IAM**: Least-privilege permissions (only read specific secrets)
4. **Logging**: CloudWatch logs with 30-day retention for audit trail
5. **Rate Limiting**: API Gateway default throttling (10K requests/second burst)

## Cost Estimate

- **Lambda**: ~$0.20/month (assuming 10K invocations)
- **API Gateway**: ~$3.50/million requests
- **Secrets Manager**: ~$0.80/month (2 secrets)
- **CloudWatch Logs**: ~$0.50/GB ingested
- **Route53**: Included in existing hosted zone

**Total**: < $5/month at typical usage

## Implementation Steps

1. ✅ Create Terraform module structure
2. ✅ Implement Lambda handler (Python)
3. ✅ Configure API Gateway with custom domain
4. ✅ Add module to dev environment
5. ⬜ Create secrets in AWS Secrets Manager (manual)
6. ⬜ Configure Mattermost slash command (manual)
7. ⬜ Configure Outline webhook (manual)
8. ⬜ Test end-to-end integration

See [MANUALINTEGR.md](MANUALINTEGR.md) for manual setup steps.
