# cochlearis-infra

Multi-cloud infrastructure as code using Terraform.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.7.0
- [tfenv](https://github.com/tfutils/tfenv) (recommended)
- [direnv](https://direnv.net/)
- [aws-vault](https://github.com/99designs/aws-vault)
- [pre-commit](https://pre-commit.com/)
- [terraform-docs](https://terraform-docs.io/)
- [tflint](https://github.com/terraform-linters/tflint)
- [checkov](https://www.checkov.io/)

## Setup

### 1. Clone the repository

```bash
git clone git@github.com:dlf-dds/cochlearis-infra.git
cd cochlearis-infra
```

### 2. Install pre-commit hooks

```bash
pre-commit install
```

### 3. Allow direnv

```bash
direnv allow
```

### 4. Bootstrap AWS (first time only)

```bash
./scripts/bootstrap-aws
```

This creates the S3 bucket and DynamoDB table for Terraform state.

## Usage

### Working with environments

```bash
cd environments/aws/dev
terraform init
terraform plan
terraform apply
```

### Formatting

```bash
./scripts/format-files
```

### Generating documentation

```bash
./scripts/update-docs
```

## Directory Structure

```
.
├── .github/workflows/     # GitHub Actions CI/CD
├── environments/          # Environment configurations
│   ├── aws/              # AWS environments
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   ├── gcp/              # GCP environments (future)
│   └── azure/            # Azure environments (future)
├── modules/              # Reusable Terraform modules
│   ├── aws/              # AWS-specific modules
│   ├── gcp/              # GCP-specific modules (future)
│   ├── azure/            # Azure-specific modules (future)
│   └── common/           # Cloud-agnostic modules
└── scripts/              # Utility scripts
```

## CI/CD

This repository uses GitHub Actions for CI/CD:

- **terraform-validate.yml**: Runs on all PRs - validates formatting, syntax, and linting
- **terraform-plan.yml**: Runs on PRs to main - generates and posts Terraform plan
- **terraform-apply.yml**: Runs on merge to main - applies changes (prod requires approval)

## Contributing

1. Create a feature branch
2. Make changes
3. Run `pre-commit run --all-files`
4. Open a pull request

---

## Addendum: Multi-Cloud Identity Access Patterns

Secure credential management for each cloud provider without storing long-lived secrets.

### AWS

Use [aws-vault](https://github.com/99designs/aws-vault) for secure credential management with STS temporary tokens:

```bash
# Add credentials to secure keychain (one-time)
aws-vault add cochlearis

# Execute commands with temporary credentials
aws-vault exec cochlearis -- terraform plan

# Or start a subshell
aws-vault exec cochlearis
```

**For CI/CD**: Use OIDC with IAM roles (no secrets stored):

```yaml
# GitHub Actions example
permissions:
  id-token: write
steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::123456789:role/github-actions
      aws-region: eu-central-1
```

### GCP

Use `gcloud` CLI with Application Default Credentials (ADC) - no additional tools needed:

```bash
# Login once (opens browser, caches credentials securely)
gcloud auth application-default login

# Set default project
gcloud config set project my-project

# Terraform/SDK automatically uses these credentials
terraform plan
```

**For service account impersonation** (recommended for elevated privileges):

```bash
gcloud auth application-default login \
  --impersonate-service-account=terraform@project.iam.gserviceaccount.com
```

**For CI/CD**: Use Workload Identity Federation (keyless auth):

```yaml
# GitHub Actions example
- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: projects/123/locations/global/workloadIdentityPools/github/providers/github
    service_account: terraform@project.iam.gserviceaccount.com
```

### Azure

Use `az` CLI with built-in credential caching:

```bash
# Login once (opens browser, caches credentials securely)
az login

# Set default subscription
az account set --subscription "My Subscription"

# Terraform/SDK automatically uses these credentials
terraform plan
```

**For service principal impersonation**:

```bash
az login --service-principal \
  --username $ARM_CLIENT_ID \
  --password $ARM_CLIENT_SECRET \
  --tenant $ARM_TENANT_ID
```

**For CI/CD**: Use OIDC with Service Principal (no secrets stored):

```yaml
# GitHub Actions example
- uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

### Comparison

| Feature | AWS | GCP | Azure |
|---------|-----|-----|-------|
| CLI tool | aws-vault | gcloud | az |
| Credential storage | OS keychain | OS keyring | OS keyring |
| Session duration | 1-12 hours (configurable) | 1 hour (auto-refresh) | 1 hour (auto-refresh) |
| MFA support | Yes (via STS) | Yes (via gcloud) | Yes (via az) |
| Keyless CI/CD | OIDC + IAM roles | Workload Identity Federation | OIDC + Service Principal |

### Best Practices

1. **Never store long-lived credentials** - Use temporary tokens and OIDC where possible
2. **Use least privilege** - Create dedicated roles/service accounts for Terraform
3. **Enable MFA** - Require MFA for interactive sessions
4. **Audit access** - Enable CloudTrail (AWS), Cloud Audit Logs (GCP), or Activity Log (Azure)
5. **Rotate credentials** - If using service account keys, rotate them regularly
