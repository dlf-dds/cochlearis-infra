# Security Vulnerability Report

**Generated:** 2026-02-04 (Updated with remediation status)
**Repository:** cochlearis-infra
**Scan Type:** Manual code review + automated pattern matching

---

## 🚨 CRITICAL: AWS Credentials Exposed in Git History

**Status:** ✅ REMEDIATED (2026-02-04)

### Remediation Progress

| Step | Status | Notes |
|------|--------|-------|
| Remove tfplan from git tracking | ✅ Done | `git rm --cached` completed |
| Update .gitignore | ✅ Done | Added tfplan patterns |
| Scrub git history (BFG) | ✅ Done | tfplan removed from all commits |
| Force push to GitHub | ✅ Done | Clean history pushed |
| Rotate SES credentials | ✅ Done | New keys: `AKIA47CR2NO4QIYKWSDW`, `AKIA47CR2NO4QEG6QX7R` |
| Detach quarantine policy | ✅ Done | Policies removed from both users |
| Delete old access keys | ✅ Done | Terraform destroyed old keys |
| Respond to AWS Support | ⏳ Pending | Cases 177013174400370, 177013175300914 |

### What Happened

A Terraform plan file (`environments/aws/dev/tfplan`) was committed to git and pushed to GitHub. Terraform plan files are **binary archives containing plaintext secrets**, including AWS access keys.

AWS detected the exposure and:
1. Quarantined the compromised IAM users
2. Opened support cases: `177013174400370` and `177013175300914`

### Compromised Credentials

| IAM User | Old Access Key | New Access Key | Status |
|----------|----------------|----------------|--------|
| `cochlearis-dev-zitadel-ses` | `AKIA47CR2NO4ZSUMKMFP` (deleted) | `AKIA47CR2NO4QIYKWSDW` | ✅ Rotated |
| `cochlearis-dev-mattermost-ses` | `AKIA47CR2NO4UHWIVFWZ` (deleted) | `AKIA47CR2NO4QEG6QX7R` | ✅ Rotated |

### Root Cause

`.gitignore` was **missing patterns for Terraform plan files**:
- `tfplan`
- `*.tfplan`
- `plan.out`

**Fixed:** `.gitignore` updated to exclude these patterns.

### Remediation Steps

#### Step 1: Remove tfplan from git tracking (do this NOW)

```bash
# Remove from git index (keeps local file)
git rm --cached environments/aws/dev/tfplan

# Commit the removal
git commit -m "security: remove tfplan file containing exposed credentials"
```

#### Step 2: Scrub tfplan from git history

The file still exists in git history. Use BFG Repo-Cleaner (faster) or git filter-repo:

```bash
# Option A: BFG (recommended - faster)
# Install: brew install bfg
bfg --delete-files tfplan --no-blob-protection

# Option B: git filter-repo
# Install: brew install git-filter-repo
git filter-repo --path environments/aws/dev/tfplan --invert-paths

# After either option, clean up
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```

#### Step 3: Force push to GitHub

```bash
# WARNING: Coordinate with team - this rewrites history
git push origin main --force
```

#### Step 4: Rotate the compromised SES credentials

The easiest way is to taint the IAM access keys in Terraform and re-apply:

```bash
cd environments/aws/dev

# Taint the SES user access keys to force recreation
aws-vault exec cochlearis --no-session -- terraform taint 'module.zitadel.module.ses_user[0].aws_iam_access_key.main'
aws-vault exec cochlearis --no-session -- terraform taint 'module.mattermost.module.ses_user[0].aws_iam_access_key.main'

# Apply to create new keys
aws-vault exec cochlearis --no-session -- terraform apply

# Force ECS redeploy to pick up new credentials
aws-vault exec cochlearis --no-session -- aws ecs update-service \
  --cluster cochlearis-dev-cluster --service zitadel --force-new-deployment --region eu-central-1

aws-vault exec cochlearis --no-session -- aws ecs update-service \
  --cluster cochlearis-dev-cluster --service mattermost --force-new-deployment --region eu-central-1
```

#### Step 5: Detach quarantine policy

After keys are rotated:

```bash
aws-vault exec cochlearis --no-session -- aws iam detach-user-policy \
  --user-name cochlearis-dev-zitadel-ses \
  --policy-arn arn:aws:iam::aws:policy/AWSCompromisedKeyQuarantineV3

aws-vault exec cochlearis --no-session -- aws iam detach-user-policy \
  --user-name cochlearis-dev-mattermost-ses \
  --policy-arn arn:aws:iam::aws:policy/AWSCompromisedKeyQuarantineV3
```

#### Step 6: Delete old compromised keys

```bash
aws-vault exec cochlearis --no-session -- aws iam delete-access-key \
  --user-name cochlearis-dev-zitadel-ses \
  --access-key-id AKIA47CR2NO4ZSUMKMFP

aws-vault exec cochlearis --no-session -- aws iam delete-access-key \
  --user-name cochlearis-dev-mattermost-ses \
  --access-key-id AKIA47CR2NO4UHWIVFWZ
```

#### Step 7: Respond to AWS Support Cases

Respond to both support cases confirming:
1. Keys have been rotated
2. Old keys deleted
3. Git history scrubbed
4. `.gitignore` updated to prevent recurrence

### Why Initial Scan Missed This

1. **Binary file:** `tfplan` is a zip archive, not searchable text
2. **Pattern gap:** Searched for AKIA patterns in text files, not binary
3. **Gitignore assumption:** Assumed standard terraform gitignore was complete

### Prevention

Added to `.gitignore`:
```
tfplan
*.tfplan
**/tfplan
**/*.tfplan
plan.out
*.plan
```

---

## Executive Summary

**Overall Assessment: ~~LOW RISK~~ → CRITICAL (Active Incident)**

Credential exposure detected by AWS. Two SES SMTP user access keys were exposed via a committed tfplan file. AWS has quarantined the affected IAM users. Immediate remediation required.

---

## Credential Scan Results

### Current Repository Files

| Check | Status | Details |
|-------|--------|---------|
| AWS Access Keys (AKIA pattern) | ✅ PASS | No AWS access keys found |
| Private Keys | ✅ PASS | No RSA/DSA/EC private keys found |
| Hardcoded Passwords | ✅ PASS | All passwords reference Secrets Manager ARNs |
| API Keys/Tokens | ✅ PASS | Tokens passed via environment (not hardcoded) |
| .env Files | ✅ PASS | `.envrc` files contain only non-sensitive config |
| terraform.tfvars | ✅ PASS | Properly gitignored; only `.example` files tracked |

### Git History Analysis

| Check | Status | Details |
|-------|--------|---------|
| Historical AWS Keys | ✅ PASS | No AWS credentials in commit history |
| Historical Private Keys | ✅ PASS | No private keys ever committed |
| Historical Secrets | ✅ PASS | No plaintext secrets found in diffs |
| tfvars History | ✅ PASS | Only `.tfvars.example` files tracked |

---

## Infrastructure Security Review

### Encryption Status

| Resource Type | Encrypted | Notes |
|--------------|-----------|-------|
| RDS PostgreSQL | ✅ Yes | `storage_encrypted = true` |
| RDS MySQL | ✅ Yes | `storage_encrypted = true` |
| EFS | ✅ Yes | `encrypted = true` |
| S3 Buckets | ✅ Yes | Default encryption enabled |
| ElastiCache Redis | ⚠️ Partial | In-transit encryption not configured |

### Network Security

| Control | Status | Notes |
|---------|--------|-------|
| RDS Publicly Accessible | ✅ Secure | `publicly_accessible = false` |
| Security Group Ingress | ✅ Secure | Restricted to specific security groups |
| Security Group Egress | ✅ Standard | Uses `0.0.0.0/0` (standard practice) |
| VPC Configuration | ✅ Secure | Private/public subnet separation |
| Internal ALB | ✅ Secure | Restricted to VPC CIDR (`10.0.0.0/16`) |

### IAM & Access Control

| Finding | Severity | Location |
|---------|----------|----------|
| Overly permissive S3 IAM policy | MEDIUM | [modules/aws/s3-user/main.tf:17-22](modules/aws/s3-user/main.tf#L17-L22) |
| SES wildcard resource | LOW | [modules/aws/ses-smtp-user/main.tf:22](modules/aws/ses-smtp-user/main.tf#L22) (required by SES) |
| Governance Lambda wildcards | LOW | [modules/aws/governance/main.tf](modules/aws/governance/main.tf) (expected for management functions) |

---

## Findings & Remediation Risk Assessment

### Risk Assessment Legend

| Risk Factor | Description |
|-------------|-------------|
| **Break Likelihood** | Probability of breaking currently deployed services |
| **Cascade Likelihood** | Probability of triggering fix→change→ship loops |
| **IaC Impact** | Effect on Terraform idempotence and automated spin-up/tear-down |
| **Verdict** | ✅ SAFE TO REMEDIATE / ⚠️ PROCEED WITH CAUTION / 🚫 DEFER TO TODO |

---

### MEDIUM Severity

#### 1. S3 User IAM Policy Too Permissive

**Location:** [modules/aws/s3-user/main.tf:17-22](modules/aws/s3-user/main.tf#L17-L22)

**Status:** ✅ **REMEDIATED**

**What was fixed:**
- Added required `bucket_name` variable
- Scoped IAM policy to specific bucket with least-privilege actions:
  - `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket`, `s3:GetObjectAcl`, `s3:PutObjectAcl`
- Updated policy description to include bucket name

---

### LOW Severity

#### 2. Database Deletion Protection Default

**Location:** [modules/aws/rds-postgres/variables.tf](modules/aws/rds-postgres/variables.tf), [modules/aws/rds-mysql/variables.tf](modules/aws/rds-mysql/variables.tf)

**Status:** ✅ **REMEDIATED**

**What was fixed:**
- Changed default for `deletion_protection` from `false` to `true` in both RDS modules
- Added explicit documentation in variable description about the two-step destroy workflow
- Added documentation in [docs/GOTCHAS.md](docs/GOTCHAS.md) explaining the destroy process

**Two-step destroy workflow documented:**
1. Set `deletion_protection = false` and `terraform apply`
2. Run `terraform destroy`

**Note:** Dev environment can override to `false` if automated tear-down is required.

---

#### 3. No CloudTrail Configured

**Status:** ✅ **REMEDIATED** (Module created, ready to deploy)

**What was created:**
- New CloudTrail module at [modules/aws/cloudtrail/](modules/aws/cloudtrail/)
- Features:
  - Encrypted S3 bucket for log storage with lifecycle policies
  - Multi-region trail support
  - Optional CloudWatch Logs integration for real-time alerting
  - Optional S3 data events logging

**To deploy:**
```hcl
module "cloudtrail" {
  source = "../../../modules/aws/cloudtrail"

  project     = var.project
  environment = var.environment
}
```

**Cost Impact:** ~$2-5/month for basic CloudTrail (management events only).

---

#### 4. No WAF on Public ALB

**Risk:** ALB exposed without Web Application Firewall protection.

#### Remediation Risk Assessment

| Factor | Rating | Analysis |
|--------|--------|----------|
| **Break Likelihood** | 🟡 MEDIUM | Overly aggressive WAF rules can block legitimate traffic (false positives). |
| **Cascade Likelihood** | 🟡 MEDIUM | WAF misconfigurations often trigger debugging cycles (rule tuning). |
| **IaC Impact** | 🟢 NONE | Standard Terraform resource; fully idempotent. |

**Verdict:** ⚠️ PROCEED WITH CAUTION

**Risks:**
1. Rate limiting rules may block legitimate users during bursts
2. SQL injection rules may false-positive on legitimate form submissions
3. Requires monitoring and rule tuning after deployment

**Recommended Action:**
- **Defer to production hardening phase**
- When implementing, start with COUNT mode (log only, don't block) for 1-2 weeks
- Graduate to BLOCK mode after validating no false positives

**🚫 MOVED TO TODO BUCKET** - Requires monitoring/tuning cycle not suitable for quick fix.

---

#### 5. ElastiCache Redis In-Transit Encryption

**Location:** [modules/aws/elasticache-redis/main.tf](modules/aws/elasticache-redis/main.tf)

**Risk:** Data in transit between application and Redis is unencrypted.

#### Remediation Risk Assessment

| Factor | Rating | Analysis |
|--------|--------|----------|
| **Break Likelihood** | 🔴 **HIGH** | Enabling transit encryption **FORCES CLUSTER RECREATION**. Cannot be done in-place. |
| **Cascade Likelihood** | 🔴 **HIGH** | Requires: (1) cluster recreation, (2) app config changes for TLS, (3) connection string updates, (4) potential session loss. |
| **IaC Impact** | 🔴 **SEVERE** | Triggers `destroy/create` cycle. Breaks idempotence during migration. Causes service downtime. |

**Verdict:** 🚫 DEFER TO TODO

**Why This Cannot Be Done Safely:**

1. **AWS Limitation:** ElastiCache `transit_encryption_enabled` is an immutable parameter. Changing it forces resource replacement.

2. **Service Impact:**
   - Outline uses Redis for sessions/cache
   - Cluster recreation = all cached data lost
   - Session tokens invalidated = all users logged out
   - Potential service downtime during switchover

3. **Application Changes Required:**
   - Connection string must change to `rediss://` (TLS)
   - App must be configured to accept Redis TLS certificates
   - Requires coordinated deployment: new Redis → app update → cutover

4. **IaC Breakage:**
   - `terraform apply` will show `destroy/create` for Redis
   - Non-idempotent: running twice produces different results during migration
   - Cannot safely automate in CI/CD without human oversight

**🚫 MOVED TO TODO BUCKET** - Requires planned maintenance window and coordinated migration.

**Future Migration Plan (for TODO):**
1. Create new Redis cluster with encryption enabled
2. Update Outline to connect to new cluster
3. Deploy Outline with new connection string
4. Verify functionality
5. Destroy old cluster
6. Update Terraform to reflect final state

---

## Information Exposure (Non-Critical)

The following non-secret identifiers are present in tracked files (these are expected and not credentials):

| Item | File | Risk Level |
|------|------|------------|
| Route53 Zone ID | terraform.tfvars | None |
| Google OAuth Client ID | terraform.tfvars | None (public value) |
| Azure Tenant ID | terraform.tfvars | None (public value) |
| Azure Client ID | terraform.tfvars | None (public value) |
| Slack Client ID | terraform.tfvars | None (public value) |
| AWS Account ID (in ARNs) | terraform.tfvars | Minimal |

**Note:** OAuth Client IDs and Tenant IDs are intentionally public values. Only the corresponding secrets (stored in AWS Secrets Manager) need protection.

---

## Git Security Configuration

### .gitignore Analysis

The repository properly excludes sensitive files:

| Pattern | Protected |
|---------|-----------|
| `*.tfvars` | ✅ Yes (except `.example`) |
| `*.tfstate*` | ✅ Yes |
| `.terraform/` | ✅ Yes |
| `.env*` | ✅ Yes |
| `.envrc.local` | ✅ Yes |

### Tracked Sensitive File Verification

```
environments/aws/dev/terraform.tfvars → IGNORED ✅
environments/aws/dev/terraform.tfvars.example → Tracked (no secrets) ✅
```

---

## Compliance Checklist

| Control | Status |
|---------|--------|
| Secrets in Secrets Manager | ✅ Implemented |
| Encryption at rest | ✅ Implemented |
| Network isolation | ✅ Implemented |
| Least privilege IAM | ✅ Implemented (s3-user module now properly scoped) |
| Audit logging (CloudTrail) | ✅ Module created (ready to deploy) |
| WAF protection | ⏳ Deferred (requires tuning cycle) |
| MFA for console access | ℹ️ External to IaC |

---

## Action Items Summary

### ✅ Completed Remediations

| Item | Status | Notes |
|------|--------|-------|
| Fix s3-user module | ✅ Done | Scoped to specific bucket with least-privilege actions |
| CloudTrail module | ✅ Done | Module created, ready to deploy |
| Database deletion protection | ✅ Done | Defaults to true, docs updated |
| .gitignore for tfplan | ✅ Done | Prevents future credential exposure |

### ✅ Completed (Manual Steps)

| Item | Status | Completed |
|------|--------|-----------|
| Scrub git history | ✅ Done | BFG removed tfplan, force pushed to GitHub |
| Rotate SES credentials | ✅ Done | New access keys created via Terraform |
| Detach quarantine policies | ✅ Done | AWS policies removed from IAM users |
| Delete old access keys | ✅ Done | Terraform destroyed compromised keys |

### ⏳ Pending

| Item | Status | Next Action |
|------|--------|-------------|
| AWS Support response | ⏳ Pending | Reply to cases 177013174400370, 177013175300914 |

### 🚫 Deferred to TODO Bucket

| Item | Risk | Why Deferred |
|------|------|--------------|
| WAF on ALB | 🟡 Medium | Requires tuning cycle; false positive risk |
| Redis in-transit encryption | 🔴 High | Forces cluster recreation; service downtime; requires coordinated migration |

---

## TODO Bucket (Deferred Items)

These items require planned maintenance windows or extended implementation cycles:

### 1. WAF Implementation
- **Reason Deferred:** Risk of false positives blocking legitimate traffic
- **Prerequisites:**
  - Set up CloudWatch alarms for WAF metrics
  - Plan 2-week COUNT mode observation period
  - Document rule tuning procedure
- **Estimated Effort:** 2-3 iterations of deploy → observe → tune

### 2. Redis In-Transit Encryption
- **Reason Deferred:** Forces cluster recreation; breaks idempotence during migration
- **Prerequisites:**
  - Plan maintenance window (expect 15-30 min downtime)
  - Test TLS connection in non-prod first
  - Coordinate app config changes
- **Migration Steps:**
  1. Create new encrypted Redis cluster (parallel)
  2. Update app connection string to new cluster
  3. Deploy app changes
  4. Verify sessions/cache working
  5. Remove old cluster from Terraform state
  6. Destroy old cluster
  7. Rename new cluster in Terraform (if needed)
- **Estimated Effort:** Half-day with testing

---

## Scan Methodology

1. **Pattern Matching:** Searched for AWS key patterns (AKIA), private key headers, common secret variable names
2. **Git History Analysis:** Scanned all commits for historical secret exposure
3. **Terraform Review:** Analyzed IAM policies, security groups, encryption settings
4. **Configuration Review:** Verified .gitignore, checked for tracked sensitive files
5. **Remediation Risk Analysis:** Evaluated each fix for production impact, cascade effects, and IaC compatibility

---

*Report generated by security audit on 2026-02-04*
