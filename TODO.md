# TODO: Mattermost ↔ Outline Bridge Activation

The bridge infrastructure has been deployed. Complete these steps to activate integration.

## Remaining Steps

### 1. Create Outline API Key
- [ ] Log into Outline (`https://wiki.dev.almondbread.org`)
- [ ] Settings → API Tokens → Create new token named `mattermost-bridge`
- [ ] Copy the token immediately

### 2. Get Outline Collection ID
- [ ] Navigate to target collection in Outline
- [ ] Copy collection ID from URL: `https://wiki.../collection/{COLLECTION_ID}`

### 3. Store Outline Secret in AWS
```bash
aws-vault exec cochlearis --no-session -- aws secretsmanager create-secret \
  --name cochlearis-dev-outline-api-key \
  --secret-string '{"api_key":"YOUR_OUTLINE_API_TOKEN_HERE"}' \
  --region eu-central-1
```

### 4. Create Mattermost Incoming Webhook
- [ ] Log into Mattermost (`https://mm.dev.almondbread.org`)
- [ ] Menu → Integrations → Incoming Webhooks → Add
- [ ] Configure: Title=`Outline Notifications`, Channel=target channel
- [ ] Copy webhook URL

### 5. Store Mattermost Secret in AWS
```bash
aws-vault exec cochlearis --no-session -- aws secretsmanager create-secret \
  --name cochlearis-dev-mattermost-webhook \
  --secret-string '{"webhook_url":"https://mm.dev.almondbread.org/hooks/YOUR_WEBHOOK_ID"}' \
  --region eu-central-1
```

### 6. Update Terraform and Apply
Edit `environments/aws/dev/terraform.tfvars`:
```hcl
enable_mm_outline_bridge      = true
outline_api_key_secret_arn    = "arn:aws:secretsmanager:eu-central-1:891377314745:secret:cochlearis-dev-outline-api-key-XXXXXX"
mattermost_webhook_secret_arn = "arn:aws:secretsmanager:eu-central-1:891377314745:secret:cochlearis-dev-mattermost-webhook-XXXXXX"
outline_default_collection_id = "YOUR_COLLECTION_ID"
```

Then apply:
```bash
cd environments/aws/dev
aws-vault exec cochlearis --no-session -- terraform apply
```

### 7. Configure Mattermost Slash Command
- [ ] Mattermost → Integrations → Slash Commands → Add
- [ ] Trigger: `outline`
- [ ] Request URL: `https://bridge.dev.almondbread.org/bridge`
- [ ] Method: POST

### 8. Configure Outline Webhook
- [ ] Outline → Settings → Webhooks → New webhook
- [ ] URL: `https://bridge.dev.almondbread.org/bridge`
- [ ] Events: `documents.publish`, `documents.update`

### 9. Test Integration
- [ ] Test slash command: `/outline create "Test Doc" "Content here"`
- [ ] Test webhook: Publish a document in Outline, verify Mattermost notification

---

See [MANUALINTEGR.md](MANUALINTEGR.md) for detailed instructions and troubleshooting.
