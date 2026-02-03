# Mattermost ↔ Outline Bridge Manual Integration Guide

After deploying the bridge infrastructure with Terraform, complete these manual steps to activate the bi-directional integration.

---

## Prerequisites

- Bridge module deployed: `https://bridge.dev.almondbread.org/bridge`
- Admin access to Mattermost
- Admin access to Outline
- AWS CLI configured with `aws-vault exec cochlearis`

---

## Step 1: Create Outline API Key

### 1.1 Generate API Token in Outline

1. Log into Outline: `https://wiki.dev.almondbread.org`
2. Click your avatar → **Settings**
3. Navigate to **API Tokens** (or **Personal API Tokens**)
4. Click **Create new token**
5. Name it: `mattermost-bridge`
6. **Copy the token immediately** (you won't see it again)

### 1.2 Get Default Collection ID

1. In Outline, navigate to the collection where you want new docs created
2. Click the collection name
3. Copy the collection ID from the URL: `https://wiki.../collection/{COLLECTION_ID}`
   - Example: `abc123def-456-789-abc-def012345678`

### 1.3 Store in AWS Secrets Manager

```bash
aws-vault exec cochlearis --no-session -- aws secretsmanager create-secret \
  --name cochlearis-dev-outline-api-key \
  --secret-string '{"api_key":"YOUR_OUTLINE_API_TOKEN_HERE"}' \
  --region eu-central-1
```

**Expected output:**
```json
{
    "ARN": "arn:aws:secretsmanager:eu-central-1:891377314745:secret:cochlearis-dev-outline-api-key-XXXXXX",
    "Name": "cochlearis-dev-outline-api-key"
}
```

Save this ARN for Terraform configuration.

---

## Step 2: Create Mattermost Incoming Webhook

### 2.1 Create Incoming Webhook

1. Log into Mattermost: `https://mm.dev.almondbread.org`
2. Click the menu (≡) → **Integrations**
3. Click **Incoming Webhooks** → **Add Incoming Webhook**
4. Configure:
   - **Title:** `Outline Notifications`
   - **Description:** `Receives document notifications from Outline wiki`
   - **Channel:** Select the channel (e.g., `#engineering`, `#docs`)
   - **Username:** `Outline` (optional)
   - **Profile Picture:** (optional - can use a book emoji icon)
5. Click **Save**
6. **Copy the webhook URL** (format: `https://mm.dev.almondbread.org/hooks/abc123xyz`)

### 2.2 Store in AWS Secrets Manager

```bash
aws-vault exec cochlearis --no-session -- aws secretsmanager create-secret \
  --name cochlearis-dev-mattermost-webhook \
  --secret-string '{"webhook_url":"https://mm.dev.almondbread.org/hooks/YOUR_WEBHOOK_ID"}' \
  --region eu-central-1
```

Save this ARN for Terraform configuration.

---

## Step 3: Create Mattermost Slash Command

### 3.1 Create Custom Slash Command

1. In Mattermost: Menu (≡) → **Integrations**
2. Click **Slash Commands** → **Add Slash Command**
3. Configure:
   - **Title:** `Create Outline Doc`
   - **Description:** `Create a new document in Outline wiki`
   - **Command Trigger Word:** `outline`
   - **Request URL:** `https://bridge.dev.almondbread.org/bridge`
   - **Request Method:** `POST`
   - **Response Username:** `Outline Bridge` (optional)
   - **Autocomplete:** Enable
   - **Autocomplete Hint:** `create "Title" "Content"`
   - **Autocomplete Description:** `Create a new Outline document`
4. Click **Save**

### 3.2 Test the Slash Command

In any Mattermost channel, type:
```
/outline create "Test Document" "This is a test document created from Mattermost."
```

You should see a response with a link to the newly created document.

---

## Step 4: Configure Outline Webhook

### 4.1 Create Webhook in Outline

1. In Outline: Settings → **Webhooks**
2. Click **New webhook**
3. Configure:
   - **Name:** `Mattermost Notifications`
   - **URL:** `https://bridge.dev.almondbread.org/bridge`
   - **Events:** Select:
     - ✅ `documents.publish`
     - ✅ `documents.update`
     - ✅ `documents.delete` (optional)
     - ✅ `documents.archive` (optional)
4. Click **Save**

### 4.2 Test the Webhook

1. Create or publish a document in Outline
2. Check your Mattermost channel - you should see a notification

---

## Step 5: Update Terraform Configuration

Add the secrets ARNs and collection ID to your Terraform configuration:

### 5.1 Add Variables (if not already present)

In `environments/aws/dev/variables.tf`:

```hcl
variable "outline_api_key_secret_arn" {
  description = "ARN of the Outline API key secret"
  type        = string
  default     = ""
}

variable "mattermost_webhook_secret_arn" {
  description = "ARN of the Mattermost webhook secret"
  type        = string
  default     = ""
}

variable "outline_default_collection_id" {
  description = "Default Outline collection ID for new documents"
  type        = string
  default     = ""
}
```

### 5.2 Set Values

In `environments/aws/dev/terraform.tfvars`:

```hcl
# Mattermost <-> Outline Bridge
outline_api_key_secret_arn    = "arn:aws:secretsmanager:eu-central-1:891377314745:secret:cochlearis-dev-outline-api-key-XXXXXX"
mattermost_webhook_secret_arn = "arn:aws:secretsmanager:eu-central-1:891377314745:secret:cochlearis-dev-mattermost-webhook-XXXXXX"
outline_default_collection_id = "YOUR_COLLECTION_ID"
```

### 5.3 Apply Configuration

```bash
cd environments/aws/dev
aws-vault exec cochlearis --no-session -- terraform apply
```

---

## Troubleshooting

### Slash Command Returns Error

**Check Lambda logs:**
```bash
aws-vault exec cochlearis --no-session -- aws logs tail \
  /aws/lambda/cochlearis-dev-mm-outline-bridge \
  --region eu-central-1 --follow
```

**Common issues:**
- Missing or invalid API key → Check Secrets Manager secret format
- Invalid collection ID → Verify collection exists and ID is correct
- Network error → Check Lambda can reach Outline (VPC config)

### Webhook Not Triggering

**Check Outline webhook status:**
1. Outline Settings → Webhooks
2. Check the webhook shows as "Active"
3. Look for delivery failures

**Test webhook endpoint directly:**
```bash
curl -X POST https://bridge.dev.almondbread.org/bridge \
  -H "Content-Type: application/json" \
  -d '{"event":"documents.publish","payload":{"model":{"title":"Test","url":"/doc/test-123"}}}'
```

### Mattermost Not Receiving Notifications

**Check webhook URL:**
```bash
# Test webhook directly
curl -X POST https://mm.dev.almondbread.org/hooks/YOUR_WEBHOOK_ID \
  -H "Content-Type: application/json" \
  -d '{"text":"Test notification from bridge"}'
```

---

## Security Notes

1. **API Keys:** Stored in AWS Secrets Manager, not in environment variables or code
2. **Webhook URLs:** Incoming webhook URLs should be treated as secrets
3. **Rate Limiting:** API Gateway has default throttling (10K req/s burst)
4. **Logging:** All requests logged to CloudWatch (30-day retention)

---

## Quick Reference

| Component | URL/Value |
|-----------|-----------|
| Bridge Endpoint | `https://bridge.dev.almondbread.org/bridge` |
| Outline | `https://wiki.dev.almondbread.org` |
| Mattermost | `https://mm.dev.almondbread.org` |
| Lambda Logs | `/aws/lambda/cochlearis-dev-mm-outline-bridge` |
| API Gateway Logs | `/aws/apigateway/cochlearis-dev-bridge` |

---

## Usage Examples

### Create Document from Mattermost

```
/outline create "Sprint 42 Retro Notes" "## What went well\n\n- Shipped feature X\n- Good collaboration\n\n## What to improve\n\n- More testing"
```

### View Notifications

Documents published/updated in Outline will appear in your configured Mattermost channel:

```
:rocket: **Document published:** [Sprint 42 Retro Notes](https://wiki.dev.almondbread.org/doc/sprint-42-retro-notes-abc123)
```
