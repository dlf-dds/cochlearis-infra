# Phoenix Architecture Readiness

This document assesses our ability to completely destroy and rebuild infrastructure from scratch — the "phoenix" capability that enables true infrastructure immutability.

## Current Status: 60% Ready

We can rebuild infrastructure, but **data will be lost** and **manual steps are required**.

---

## What Works Today

| Capability | Status | Notes |
|------------|--------|-------|
| Terraform creates all infrastructure | ✅ | VPC, ECS, RDS, ALB, etc. |
| Terraform destroys cleanly | ✅ | No orphaned resources |
| Environments are isolated | ✅ | Dev destruction doesn't affect prod |
| RDS has automated backups | ✅ | 7-day retention |
| Secrets auto-generate | ✅ | New passwords on each apply |
| Certificates auto-validate | ✅ | DNS validation via Route53 |
| State is versioned | ✅ | S3 versioning enabled |

---

## What Blocks Phoenix Rebuilds

### 🔴 Critical: Data Loss on Destroy

#### EFS (Zulip Data + Sidecar PostgreSQL)
```
Location: modules/aws/efs/main.tf
Problem:  No backup snapshots configured
Impact:   terraform destroy = Zulip database and files GONE FOREVER
Fix:      Add AWS Backup plan with daily snapshots
Effort:   1 day
```

#### S3 Buckets (User Uploads)
```
Location: modules/aws/apps/zulip/main.tf (lines 124-130)
          modules/aws/apps/bookstack/main.tf (lines 82-88)
Problem:  No versioning, no lifecycle rules
Impact:   terraform destroy = User uploads GONE FOREVER
Fix:      Enable versioning, add lifecycle rules
Effort:   2 hours
```

#### Encryption Keys Regenerate
```
Location: modules/aws/apps/zitadel/main.tf (lines 56-82)
          modules/aws/apps/bookstack/main.tf
Problem:  random_password resources create NEW keys on each apply
Impact:   After rebuild, apps can't decrypt data from RDS backup
Fix:      Add lifecycle { ignore_changes } after initial creation
Effort:   1 day
```

### 🔴 Critical: Manual Steps Required

#### Zitadel OIDC Bootstrap
```
Location: environments/aws/dev/bootstrap-zitadel-oidc.sh
Problem:  Requires manual login to Zitadel UI to create service account
Impact:   20 minutes manual work after each rebuild
Fix:      Automate via Zitadel Management API
Effort:   2 days
```

#### SES Domain Verification
```
Location: environments/aws/dev/manual.sh (lines 31-94)
Problem:  Requires manual DNS record creation
Impact:   15 minutes manual work + DNS propagation
Fix:      Automate DNS record creation via Terraform
Effort:   1 day
```

### 🟡 Medium: Missing Documentation

#### No Restore Procedures
```
Problem:  RDS backups exist but no documented restore process
Impact:   During incident, operator must figure it out under pressure
Fix:      Document and test restore procedures
Effort:   1 day
```

---

## Current Rebuild Experience

```bash
# Today's reality (broken phoenix)

terraform destroy -auto-approve
# ⚠️  EFS data: DELETED (no backup)
# ⚠️  S3 uploads: DELETED (no versioning)
# ⚠️  Encryption keys: DELETED (will regenerate as new)

terraform apply -auto-approve
# ✅ Infrastructure created (~10 minutes)
# ❌ Zitadel: Fresh install, old RDS backup unusable (wrong encryption key)
# ❌ Zulip: No data (EFS was empty)
# ❌ BookStack: Fresh install, old data encrypted with old key
# ❌ OIDC: Broken (need manual Zitadel PAT creation)
# ❌ Email: Broken (need manual SES DNS verification)

# Manual fixes required:
# 1. Create Zitadel service account in UI (20 min)
# 2. Add SES DNS records (15 min + propagation)
# 3. Accept that all previous data is lost

# Total time: 45+ minutes, complete data loss
```

---

## Target Rebuild Experience

```bash
# After fixes (true phoenix)

# Pre-destroy: Verify backups exist
./scripts/verify-backups.sh
# ✅ EFS snapshot: cochlearis-dev-efs-2024-01-15
# ✅ S3 versioning: enabled
# ✅ RDS snapshot: automatic daily

terraform destroy -auto-approve
# ✅ Infrastructure deleted
# ✅ EFS snapshot preserved
# ✅ S3 versions preserved
# ✅ RDS backup preserved

terraform apply -auto-approve
# ✅ Infrastructure created (~10 minutes)
# ✅ EFS restored from snapshot
# ✅ Encryption keys preserved (lifecycle ignore)
# ✅ Zitadel OIDC auto-configured
# ✅ SES auto-verified

# Total time: ~15 minutes, zero data loss
```

---

## Implementation Plan

### Phase 1: Enable Phoenix (Priority: Critical)

**Week 1-2: Data Preservation**

#### 1.1 Add EFS Backup Module
```hcl
# modules/aws/efs-backup/main.tf (new module)

resource "aws_backup_vault" "main" {
  name = "${var.project}-${var.environment}-backup-vault"
}

resource "aws_backup_plan" "efs" {
  name = "${var.project}-${var.environment}-efs-backup"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 * * ? *)"  # 3 AM daily

    lifecycle {
      delete_after = 30  # Keep 30 days
    }
  }
}

resource "aws_backup_selection" "efs" {
  name         = "${var.project}-${var.environment}-efs"
  plan_id      = aws_backup_plan.efs.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [var.efs_arn]
}
```

#### 1.2 Enable S3 Versioning
```hcl
# Add to modules/aws/apps/zulip/main.tf and bookstack/main.tf

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    id     = "retain-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}
```

#### 1.3 Protect Encryption Keys
```hcl
# Add to modules/aws/apps/zitadel/main.tf

resource "aws_secretsmanager_secret_version" "master_key" {
  secret_id = aws_secretsmanager_secret.master_key.id
  secret_string = jsonencode({
    key            = random_password.master_key.result
    admin_password = random_password.admin_password.result
  })

  lifecycle {
    ignore_changes = [secret_string]  # Don't regenerate after initial creation
  }
}
```

**Week 2-3: Automation**

#### 1.4 Automate Zitadel Bootstrap
```bash
# scripts/bootstrap-zitadel-auto.sh (new script)

#!/bin/bash
# Wait for Zitadel to be healthy
until curl -sf "https://${ZITADEL_DOMAIN}/debug/healthz"; do
  echo "Waiting for Zitadel..."
  sleep 10
done

# Create service account via Management API
# (Requires initial admin credentials from Secrets Manager)
# ... API calls to create service account and PAT
```

#### 1.5 Automate SES Verification
```hcl
# Add to SES module - create DNS records automatically

resource "aws_route53_record" "ses_verification" {
  zone_id = var.route53_zone_id
  name    = "_amazonses.${var.domain_name}"
  type    = "TXT"
  ttl     = 600
  records = [aws_ses_domain_identity.main.verification_token]
}
```

### Phase 2: Documentation (Priority: High)

#### 2.1 Create Restore Procedures
```markdown
# docs/disaster-recovery.md

## RDS Restore Procedure
1. Identify latest snapshot: `aws rds describe-db-snapshots --db-instance-identifier cochlearis-dev-zitadel`
2. Restore to new instance: `aws rds restore-db-instance-from-db-snapshot ...`
3. Update Terraform state: `terraform import module.zitadel.module.database.aws_db_instance.main ...`
4. Verify connectivity: `psql -h <endpoint> -U postgres -d zitadel`

## EFS Restore Procedure
1. Identify latest recovery point: `aws backup list-recovery-points-by-backup-vault ...`
2. Start restore job: `aws backup start-restore-job ...`
3. Update ECS task to mount restored filesystem
4. Verify data integrity
```

#### 2.2 Create Verification Script
```bash
# scripts/verify-phoenix-ready.sh

#!/bin/bash
echo "=== Phoenix Readiness Check ==="

# Check EFS backups
echo -n "EFS backup plan exists: "
aws backup list-backup-plans | grep -q "cochlearis" && echo "✅" || echo "❌"

# Check S3 versioning
echo -n "S3 versioning enabled: "
aws s3api get-bucket-versioning --bucket cochlearis-dev-zulip-uploads | grep -q "Enabled" && echo "✅" || echo "❌"

# Check encryption key protection
echo -n "Encryption keys protected: "
grep -q "ignore_changes" modules/aws/apps/zitadel/main.tf && echo "✅" || echo "❌"

echo "=== End Check ==="
```

### Phase 3: Testing (Priority: Medium)

#### 3.1 Monthly Phoenix Drill
```yaml
# .github/workflows/phoenix-drill.yml (scheduled monthly in dev)

name: Phoenix Drill (Dev Only)
on:
  schedule:
    - cron: '0 2 1 * *'  # First of each month, 2 AM

jobs:
  phoenix-drill:
    runs-on: ubuntu-latest
    environment: dev-phoenix-drill
    steps:
      - name: Backup verification
        run: ./scripts/verify-backups.sh

      - name: Terraform destroy
        run: terraform destroy -auto-approve

      - name: Terraform apply
        run: terraform apply -auto-approve

      - name: Health check
        run: ./scripts/health-check.sh

      - name: Report results
        run: ./scripts/report-phoenix-drill.sh
```

---

## Success Criteria

| Metric | Current | Target |
|--------|---------|--------|
| Time to rebuild | 45+ min | < 15 min |
| Data loss on rebuild | 100% | 0% |
| Manual steps | 3 | 0 |
| Documented procedures | Partial | Complete |
| Tested monthly | No | Yes |

---

## Risk Matrix

| Scenario | Current Risk | After Phase 1 |
|----------|--------------|---------------|
| Dev environment corrupted | 🟡 Rebuild, lose data | ✅ Rebuild, restore data |
| Staging environment corrupted | 🟡 Rebuild, lose data | ✅ Rebuild, restore data |
| Prod environment corrupted | 🔴 Major incident | 🟡 Controlled recovery |
| AWS region outage | 🔴 Total loss | 🟡 Cross-region backup (Phase 3) |
| Accidental terraform destroy | 🔴 Data loss | ✅ Recoverable |

---

## Effort Summary

| Phase | Effort | Impact |
|-------|--------|--------|
| Phase 1: Data preservation | 1 week | Enables recovery |
| Phase 1: Automation | 1 week | Eliminates manual steps |
| Phase 2: Documentation | 3 days | Reduces incident stress |
| Phase 3: Testing | 2 days setup | Validates capability |
| **Total** | **~3 weeks** | **True phoenix capability** |

---

## Next Steps

1. [ ] Create EFS backup module
2. [ ] Enable S3 versioning on upload buckets
3. [ ] Add lifecycle ignore to encryption key secrets
4. [ ] Automate Zitadel bootstrap script
5. [ ] Automate SES DNS verification
6. [ ] Document restore procedures
7. [ ] Create phoenix verification script
8. [ ] Schedule monthly phoenix drill (dev only)

---

## References

- [AWS Backup for EFS](https://docs.aws.amazon.com/efs/latest/ug/awsbackup.html)
- [S3 Versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html)
- [Terraform lifecycle meta-argument](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle)
- [Zitadel Management API](https://zitadel.com/docs/apis/introduction)
