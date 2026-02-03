# Zulip Troubleshooting - Need Help

## The Problem

**We cannot create an organization in Zulip.** Visiting `https://chat.dev.almondbread.org/new/` results in:

```
Internal server error
```

This is the most basic operation - we simply want to use Zulip at all.

---

## Infrastructure Setup

- **Deployment**: ECS Fargate with sidecar PostgreSQL container
- **Image**: `zulip/docker-zulip:9.4-0` (official docker-zulip)
- **Database**: PostgreSQL 14 sidecar (`zulip/zulip-postgresql:14`) - running in same task
- **Redis**: AWS ElastiCache (single node, t3.micro)
- **Storage**: EFS for persistent data, S3 for uploads
- **Load Balancer**: ALB with SSL termination
- **Email**: AWS SES SMTP

### Current Configuration (Environment Variables)

```
SETTING_EXTERNAL_HOST = chat.dev.almondbread.org
SETTING_OPEN_REALM_CREATION = True
SETTING_AUTHENTICATION_BACKENDS = ("zproject.backends.AzureADAuthBackend", "zproject.backends.EmailAuthBackend")
SETTING_REDIS_HOST = cochlearis-dev-zulip.pdjybc.0001.euc1.cache.amazonaws.com
SETTING_REDIS_PORT = 6379
SETTING_EMAIL_HOST = email-smtp.eu-central-1.amazonaws.com
SETTING_EMAIL_PORT = 587
SETTING_EMAIL_USE_TLS = True
DB_HOST = 127.0.0.1
DB_HOST_PORT = 5432
DB_USER = zulip
PGSSLMODE = disable
DISABLE_HTTPS = True (ALB handles SSL)
SSL_CERTIFICATE_GENERATION = self-signed
```

Secrets are injected via AWS Secrets Manager:
- `SECRETS_postgres_password`
- `SECRETS_secret_key`
- `SECRETS_email_host_user` (SES SMTP access key ID)
- `SECRETS_email_host_password` (SES SMTP password)
- `SECRETS_social_auth_azuread_oauth2_secret`

---

## What We've Tried

### 1. Initial Deployment

Deployed Zulip using terraform with docker-zulip official image. Service started, health checks pass, but organization creation fails.

### 2. Email Credentials Fix

**Issue Found**: Email credentials were not being passed correctly.

- Original config had `SETTING_EMAIL_HOST_USER = module.ses_user.name` which was the IAM user name, NOT the SMTP access key ID
- `SECRETS_email_host_password` was completely missing

**Fix Applied**: Changed to use Secrets Manager for both email username and password:
```hcl
SECRETS_email_host_user     = "${module.ses_user.smtp_credentials_secret_arn}:username::"
SECRETS_email_host_password = "${module.ses_user.smtp_credentials_secret_arn}:password::"
```

Also added the secret ARN to IAM policy for the task execution role.

**Result**: Still getting Internal Server Error.

### 3. Force Redeployment

Ran `terraform apply` and force-redeployed the ECS service to ensure new task definition is used.

**Result**: Still getting Internal Server Error.

### 4. Log Analysis

Checked CloudWatch logs for the Zulip container. Found:

**Zulip event workers are constantly crashing and restarting:**

```
2026-02-01 20:18:46,945 WARN exited: zulip_events_deferred_email_senders (exit status 1; not expected)
2026-02-01 20:18:47,139 INFO spawned: 'zulip_events_deferred_email_senders' with pid 709
2026-02-01 20:18:47,139 WARN exited: zulip_events_thumbnail (exit status 1; not expected)
... (pattern repeats continuously for all event workers)
```

Event workers that are crashing:
- `zulip_events_deferred_email_senders`
- `zulip_events_thumbnail`
- `zulip_events_missedmessage_emails`
- `zulip_events_missedmessage_mobile_notifications`
- `zulip_events_user_activity_interval`
- `zulip_events_user_activity`
- `zulip_events_email_mirror`
- `zulip_events_embed_links`
- `zulip_events_outgoing_webhooks`
- `zulip_events_embedded_bots`
- `zulip_events_digest_emails`
- `zulip_events_deferred_work`
- `zulip_events_email_senders`

**All workers exit with status 1 repeatedly, are restarted by supervisor, and crash again.**

### 5. Redis Verification

Verified Redis is available:
```json
{
    "Address": "cochlearis-dev-zulip.pdjybc.0001.euc1.cache.amazonaws.com",
    "Port": 6379,
    "Status": "available"
}
```

Could not find any "connection refused" or Redis-specific errors in logs.

### 6. PostgreSQL Verification

PostgreSQL sidecar is running and logging normally:
```
ecs-postgres/postgres/e164d5905e4b448ea86cc78305c87f4c
```

No errors visible in postgres container logs.

---

## Current State

- **ECS Service**: Running (1/1 tasks)
- **Health Checks**: Passing (ALB reports healthy - accepts 200-399,400 because nginx returns 400 without Host header)
- **PostgreSQL Sidecar**: Running
- **Redis**: Available
- **Web UI**: Loads at `https://chat.dev.almondbread.org`
- **Organization Creation**: **FAILS with Internal Server Error**

---

## What We Don't Know

1. **Why are all event workers crashing with exit status 1?**
   - Is it a Redis connection issue?
   - Is it a configuration issue?
   - Is it a missing dependency?

2. **Where are the actual Python/Django error tracebacks?**
   - CloudWatch logs only show supervisor messages
   - No Python tracebacks visible
   - nginx access/error logs not visible in CloudWatch

3. **Is email the actual cause?**
   - We fixed the credential injection but error persists
   - Maybe SES isn't verified for the domain?
   - Maybe the email configuration is still wrong?

---

## Questions for Zulip Community/Support

1. When using docker-zulip on ECS with a PostgreSQL sidecar, what logs should we check for organization creation errors?

2. Why would ALL event workers crash with exit status 1 immediately after being spawned by supervisor?

3. Is there a way to see the actual Python traceback when `/new/` returns "Internal server error"?

4. Are there any known issues with docker-zulip 9.4-0 and external Redis (AWS ElastiCache)?

5. Do we need to run any initialization commands before creating the first organization?

---

## Terraform Module Reference

The Zulip module is at: `modules/aws/apps/zulip/main.tf`

Key components:
- Uses `zulip/docker-zulip:9.4-0` container image
- PostgreSQL sidecar using `zulip/zulip-postgresql:14`
- EFS volumes for `/data` and `/var/lib/postgresql/data`
- ElastiCache Redis cluster
- S3 bucket for uploads
- SES for email
- ACM certificate with Route53 validation

---

## Workaround: Zulip Mini

While troubleshooting this issue, we've created a simplified "zulip-mini" deployment that uses docker-zulip's internal PostgreSQL and Redis (no sidecars, no external ElastiCache). This is available at:

**URL**: `https://chatmini.dev.almondbread.org`

If this works, it confirms the sidecar pattern is the issue. The zulip-mini module is at `modules/aws/apps/zulip-mini/`.

---

## Help Wanted

We just want to create an organization and start using Zulip. Any guidance on what's causing the Internal Server Error or why event workers are crashing would be greatly appreciated.

Contact: dedd.flanders@gmail.com (SETTING_ZULIP_ADMINISTRATOR)
