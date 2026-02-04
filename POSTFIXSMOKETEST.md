# Post-Credential Rotation Smoke Test

**Date:** 2026-02-04
**Context:** SES SMTP credentials rotated after tfplan exposure incident

---

## Services Affected

| Service | IAM User | New Access Key | ECS Redeployed |
|---------|----------|----------------|----------------|
| Zitadel | `cochlearis-dev-zitadel-ses` | `AKIA47CR2NO4QIYKWSDW` | Yes |
| Mattermost | `cochlearis-dev-mattermost-ses` | `AKIA47CR2NO4QEG6QX7R` | Yes |

---

## Zitadel Email Tests

### Test 1: Password Reset Email
| Step | Action |
|------|--------|
| 1 | Go to https://auth.dev.almondbread.org |
| 2 | Click "Forgot Password" or equivalent |
| 3 | Enter a test email address |
| 4 | Submit the form |
| 5 | Check inbox for password reset email |

**Expected:** Email arrives within 1-2 minutes

**Result:** [ ] Pass / [ ] Fail

---

### Test 2: New User Invitation
| Step | Action |
|------|--------|
| 1 | Log into Zitadel admin console |
| 2 | Create a new user with email |
| 3 | Trigger welcome/verification email |
| 4 | Check inbox for invitation email |

**Expected:** Email arrives within 1-2 minutes

**Result:** [ ] Pass / [ ] Fail

---

### Test 3: Check ECS Logs for SMTP Errors
```bash
aws-vault exec cochlearis --no-session -- aws logs tail \
  /ecs/cochlearis-dev-zitadel \
  --since 30m \
  --region eu-central-1 \
  --filter-pattern "SMTP"
```

**Expected:** No SMTP authentication errors

**Result:** [ ] Pass / [ ] Fail

---

## Mattermost Email Tests

### Test 1: Email Notification
| Step | Action |
|------|--------|
| 1 | Log into Mattermost as User A |
| 2 | Find User B who has email notifications enabled |
| 3 | Send User B a direct message |
| 4 | Wait for User B to be "away" or offline |
| 5 | Check User B's inbox for notification email |

**Expected:** Email arrives within configured notification delay

**Result:** [ ] Pass / [ ] Fail

---

### Test 2: User Invitation Email
| Step | Action |
|------|--------|
| 1 | Log into Mattermost as admin |
| 2 | Go to System Console > Users |
| 3 | Invite a new user via email |
| 4 | Check inbox for invitation email |

**Expected:** Email arrives within 1-2 minutes

**Result:** [ ] Pass / [ ] Fail

---

### Test 3: Check ECS Logs for SMTP Errors
```bash
aws-vault exec cochlearis --no-session -- aws logs tail \
  /ecs/cochlearis-dev-mattermost \
  --since 30m \
  --region eu-central-1 \
  --filter-pattern "smtp"
```

**Expected:** No SMTP authentication errors

**Result:** [ ] Pass / [ ] Fail

---

## General Health Checks

### ECS Service Status
```bash
aws-vault exec cochlearis --no-session -- aws ecs describe-services \
  --cluster cochlearis-dev-cluster \
  --services zitadel mattermost \
  --region eu-central-1 \
  --query 'services[*].{name:serviceName,running:runningCount,desired:desiredCount,status:status}' \
  --output table
```

**Expected:** All services show `running == desired` and `status == ACTIVE`

---

### Recent Task Failures
```bash
aws-vault exec cochlearis --no-session -- aws ecs list-tasks \
  --cluster cochlearis-dev-cluster \
  --desired-status STOPPED \
  --region eu-central-1 \
  --query 'taskArns' \
  --output table
```

**Expected:** No unexpected recent task stops (some churn during redeploy is normal)

---

## Troubleshooting

### If emails are not sending:

1. **Check Secrets Manager has new credentials:**
   ```bash
   aws-vault exec cochlearis --no-session -- aws secretsmanager get-secret-value \
     --secret-id cochlearis-dev-zitadel-ses-smtp-credentials \
     --region eu-central-1 \
     --query 'SecretString' --output text | jq .
   ```

2. **Force another ECS redeploy:**
   ```bash
   aws-vault exec cochlearis --no-session -- aws ecs update-service \
     --cluster cochlearis-dev-cluster \
     --service zitadel \
     --force-new-deployment \
     --region eu-central-1
   ```

3. **Check SES sending limits:**
   ```bash
   aws-vault exec cochlearis --no-session -- aws ses get-send-quota \
     --region eu-central-1
   ```

4. **Check SES sandbox status:**
   - If in sandbox mode, only verified email addresses can receive mail
   - Request production access via AWS console if needed

---

## Sign-off

| Tester | Date | All Tests Passed |
|--------|------|------------------|
| | | [ ] Yes / [ ] No |

**Notes:**
