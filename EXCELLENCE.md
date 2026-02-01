# Infrastructure Excellence Guide

This document explains the principles behind this repository and how to learn from it. Whether you're new to cloud engineering or have some experience, this guide will help you understand not just *what* we've built, but *why* we've built it this way.

## The Point (And What Isn't)

**This repository uses ECS Fargate, RDS, and specific AWS services. That's not the point.**

Your team might choose:
- Kubernetes (EKS, GKE, or self-managed)
- Serverless (Lambda, Cloud Run, Azure Functions)
- VMs (EC2, Compute Engine)
- A mix of everything

All of these are valid choices depending on your context, team skills, and requirements.

**What IS the point:**

1. **Idempotent, fully automated Infrastructure as Code**
2. **Good housekeeping patterns**
3. **Security as a foundation, not an afterthought**
4. **Culture and discipline that compounds over time**

The specific instantiation will differ between organizations. The principles must not.

---

## Why This Matters

Infrastructure work has a tendency to become:
- **Snowflakes** — one-off configurations that nobody understands
- **Tribal knowledge** — "ask Sarah, she set that up"
- **Risky** — "don't touch production, we don't know what will break"
- **Slow** — every change requires archaeology and fear

Good infrastructure practices flip this:
- **Repeatable** — run the same code, get the same result
- **Reusable** — solve problems once, apply everywhere
- **Understandable** — new team members can read and learn
- **Rigorous** — automated checks catch mistakes before production
- **Fiscally responsible** — know what you're spending and why
- **Dependable** — confidence to change, deploy, and recover

Most importantly: **you maintain and even gain capacity and velocity in the face of challenging technical problems.** When something breaks at 2 AM, you're not reverse-engineering mystery infrastructure — you're reading the code that built it.

---

## A Note on Humility

**This repository follows best practices. It is still not where we want it to be.**

We need to be honest about this. Despite:
- Fully automated Terraform
- Modular, reusable infrastructure
- CI/CD pipelines with validation
- Security patterns and governance
- Comprehensive documentation

...we are still far from true "phoenix architecture" — the ability to destroy everything and rebuild from scratch in minutes with zero data loss. See [PHOENIX.md](PHOENIX.md) for the gap analysis.

### Why This Matters

**Infrastructure is humbling.** Every service we deploy brings:

- **Hidden dependencies** — Zitadel needs PostgreSQL with specific extensions. Zulip needs Redis AND PostgreSQL AND specific dictionary files. BookStack needs MySQL (not PostgreSQL). Each service has opinions.

- **Initialization sequences** — It's not enough to create resources. Databases need schemas. Applications need first-run configuration. OIDC needs manual token creation. These sequences are fragile and often undocumented by upstream projects.

- **Day 2 surprises** — The health check that worked in dev returns 400 in staging. The container that ran fine locally times out on Fargate. The EFS mount that seemed fast enough becomes a bottleneck under load.

- **Day 3 debt** — Backups you assumed were happening aren't. Secrets you thought were protected can't be recovered after a rebuild. The "temporary" dev environment has been running for six months and nobody remembers what's in it.

### The Interdependency Tax

Simple-looking architectures hide complex interdependencies:

```
"Just deploy four services with SSO"

Actually:
├── Zitadel (identity provider)
│   ├── PostgreSQL (managed RDS)
│   ├── Encryption keys (must persist across rebuilds)
│   ├── First-run initialization (creates admin user, org)
│   └── Service account + PAT (manual step for OIDC)
├── BookStack (wiki)
│   ├── MySQL (not PostgreSQL — different engine)
│   ├── S3 bucket (uploads, no versioning = data loss risk)
│   ├── OIDC client (depends on Zitadel being configured)
│   └── App key (must persist or data unreadable)
├── Mattermost (chat)
│   ├── PostgreSQL (separate instance)
│   ├── OIDC via GitLab adapter (workaround for Team Edition)
│   └── File storage
├── Zulip (chat)
│   ├── PostgreSQL WITH full-text search dictionaries
│   │   └── RDS doesn't support this → sidecar container
│   │       └── EFS for persistence → no backup = data loss
│   ├── Redis (ElastiCache)
│   ├── S3 bucket (uploads)
│   ├── Memcached (optional but recommended)
│   └── OIDC (different config format than others)
└── All of this behind:
    ├── ALB with TLS termination
    ├── ACM certificates (DNS validation)
    ├── Route53 records
    ├── VPC with public/private subnets
    ├── Security groups (each service needs specific rules)
    └── IAM roles (execution role, task role, per-service policies)
```

Each arrow is a potential failure point. Each service has its own documentation, its own assumptions, its own bugs.

### What We Got Wrong (So Far)

Being specific about our gaps:

| What We Assumed | What We Found |
|-----------------|---------------|
| "RDS handles backups" | RDS backs up, but EFS doesn't. Zulip's sidecar Postgres on EFS has no backup. |
| "Secrets regenerate cleanly" | Encryption keys regenerate, making old data unreadable. |
| "Terraform destroy/apply = phoenix" | Manual steps required: Zitadel PAT, SES verification. Data lost without explicit backup. |
| "Four services, straightforward" | Each service has 5-10 dependencies with specific requirements. |
| "ARM64 works everywhere" | Zulip has no ARM64 image. Had to add Mattermost as alternative for local dev. |
| "Health checks are simple" | Zulip returns 400 on `/health` when not fully initialized. ALB marks it unhealthy. Took hours to debug. |

### The Lesson

**Do not underestimate:**

1. **Complexity cost** — Every service you add multiplies complexity, it doesn't just add to it. Four services isn't 4x complexity, it's closer to 4² when you account for interdependencies.

2. **Day 3 operations** — Getting something deployed is maybe 30% of the work. Keeping it running, backed up, recoverable, and maintainable is the other 70%.

3. **Upstream assumptions** — Open source projects assume their own happy path. Zitadel assumes you'll use their cloud or run locally. Zulip assumes bare metal or their own Docker setup. Adapting to your infrastructure is on you.

4. **The gap between "working" and "production-ready"** — This infrastructure "works" — services run, users can log in. But it's not production-ready until we can confidently destroy and rebuild it, recover from failures, and hand it off to someone else to maintain.

### Why We Document This

Most infrastructure repositories show the happy path. They don't show:
- The three days spent debugging Zitadel's Login V2 404 errors
- The realization that Zulip literally cannot run on ARM Macs
- The moment you discover EFS has no automatic backups
- The manual steps that break the "fully automated" promise

We document these in [gotchas.md](gotchas.md) and [PHOENIX.md](PHOENIX.md) because:

1. **Future us will forget** — In six months, we won't remember why we made certain choices
2. **New team members need context** — Not just what, but why and what went wrong
3. **Honesty builds trust** — If we only document successes, the documentation can't be trusted
4. **Problems are learning opportunities** — But only if we write them down

**The goal isn't perfection. The goal is continuous improvement with honest assessment of where we are.**

---

## Repository Structure

```
cochlearis-infra/
├── environments/           # Where infrastructure is instantiated
│   └── aws/
│       ├── dev/           # Development environment
│       ├── staging/       # Staging environment
│       └── prod/          # Production environment
├── modules/               # Reusable building blocks
│   └── aws/
│       ├── vpc/           # Network foundation
│       ├── ecs-cluster/   # Container orchestration
│       ├── ecs-service/   # Individual services
│       ├── rds-postgres/  # Managed databases
│       └── apps/          # Application-specific modules
│           ├── zitadel/   # Identity provider
│           ├── bookstack/ # Documentation
│           └── ...
├── local/                 # Local development (Docker Compose)
├── scripts/               # Automation scripts
├── .github/workflows/     # CI/CD automation
└── docs/                  # Additional documentation
```

### The Three Layers

**Layer 1: Infrastructure Modules** (`modules/aws/`)
- Single-purpose, reusable components
- VPC, databases, load balancers, caching
- No application-specific logic

**Layer 2: Application Modules** (`modules/aws/apps/`)
- Compose infrastructure modules for specific applications
- Contain application-specific configuration
- Still reusable across environments

**Layer 3: Environments** (`environments/aws/`)
- Wire everything together for a specific deployment
- Environment-specific values (instance sizes, counts, budgets)
- The only place that actually creates resources

---

## Principle 1: Idempotent Infrastructure as Code

### What This Means

**Idempotent**: Running the same code multiple times produces the same result.

```bash
# Run this 100 times, get the same infrastructure
terraform apply
```

This seems simple but has profound implications:

1. **No manual steps** — If it's not in code, it doesn't exist
2. **Reproducible** — Delete everything, run the code, get it back
3. **Auditable** — Git history shows every change, who made it, and when
4. **Reviewable** — Pull requests for infrastructure, just like application code

### How We Implement It

**Everything is in Terraform:**
```hcl
# modules/aws/rds-postgres/main.tf
resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-${var.identifier}"
  engine     = "postgres"
  # ... all configuration in code
}
```

**No ClickOps:**
- AWS Console is for viewing, not editing
- Changes go through pull requests
- CI/CD applies changes automatically

**State is managed:**
```hcl
# environments/aws/dev/terraform.tf
backend "s3" {
  bucket         = "cochlearis-infra-tf-state"
  key            = "aws/dev/terraform.tfstate"
  dynamodb_table = "cochlearis-infra-tf-lock"  # Prevents concurrent changes
  encrypt        = true
}
```

### What You Should Learn

1. **Read `environments/aws/dev/main.tf`** — See how modules compose together
2. **Read any module's `variables.tf`** — Understand what's configurable
3. **Run `terraform plan`** — See what would change before applying
4. **Check `.github/workflows/`** — See how CI/CD automates everything

---

## Principle 2: Good Housekeeping Patterns

Infrastructure without maintenance becomes legacy. These patterns prevent decay.

### Consistent Naming

Every resource follows: `{project}-{environment}-{purpose}`

```hcl
# Predictable, searchable, understandable
cochlearis-dev-zitadel-db
cochlearis-prod-alb
cochlearis-staging-ecs-cluster
```

**Why it matters:** When you're debugging at 2 AM, you can find resources by name. When the bill arrives, you can allocate costs.

### Tagging Strategy

Every resource gets tagged:

```hcl
# environments/aws/dev/providers.tf
provider "aws" {
  default_tags {
    tags = {
      Project     = "cochlearis"
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = "dedd.flanders@gmail.com"
      Lifecycle   = "temporary"  # or "persistent"
    }
  }
}
```

**Why it matters:**
- **Cost allocation** — Know what each project/environment costs
- **Automation** — Scripts can find and act on tagged resources
- **Accountability** — Know who to contact about a resource
- **Lifecycle management** — Automatically clean up temporary resources

### Documentation That Lives With Code

```
modules/aws/ecs-service/
├── main.tf
├── variables.tf
├── outputs.tf
└── README.md          # Auto-generated, always current
```

Each module has a README generated by `terraform-docs`. It's always accurate because it's generated from the code.

**Why it matters:** Documentation that's separate from code becomes stale. Documentation generated from code stays current.

### The Gotchas File

See `gotchas.md` — a living document of things that went wrong and how we fixed them.

```markdown
### Zitadel Login V2 (404 Not Found)

Zitadel v4+ has Login V2 enabled by default, but Login V2 is a
**separate application** that must be deployed alongside the backend...

**Solution**: Disable Login V2 to use the classic Login V1:
```

**Why it matters:** Mistakes are learning opportunities. Documented mistakes prevent the same learning twice.

---

## Principle 3: Security as Foundation

Security isn't a feature you add later. It's built into every layer.

### Network Segregation

```
Internet
    │
    ▼ (HTTPS only)
┌─────────────────┐
│  ALB (Public)   │  ← Only thing exposed to internet
└────────┬────────┘
         │ (Internal HTTP)
         ▼
┌─────────────────┐
│  ECS (Private)  │  ← No public IP, no direct access
└────────┬────────┘
         │ (TCP 5432)
         ▼
┌─────────────────┐
│  RDS (Private)  │  ← Only accessible from ECS
└─────────────────┘
```

**Why it matters:** Even if an attacker compromises one layer, they can't easily move to others.

### Secrets Management

**Never in code:**
```hcl
# BAD - Never do this
password = "my-secret-password"

# GOOD - Reference from Secrets Manager
secrets = {
  DB_PASSWORD = "${module.database.secret_arn}:password::"
}
```

**Auto-generated and stored:**
```hcl
# modules/aws/rds-postgres/main.tf
resource "random_password" "master" {
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret_version" "master_password" {
  secret_id = aws_secretsmanager_secret.master_password.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    # ... connection details
  })
}
```

**Why it matters:** Secrets in code end up in Git history forever. Secrets in Secrets Manager can be rotated, audited, and access-controlled.

### No Long-Lived Credentials

**For developers (aws-vault):**
```bash
# Temporary STS credentials, not permanent access keys
aws-vault exec dev -- terraform plan
```

**For CI/CD (OIDC):**
```yaml
# .github/workflows/terraform-apply.yml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/github-actions
    # No secrets stored - GitHub's OIDC token is exchanged for AWS credentials
```

**Why it matters:** Long-lived credentials get leaked, shared, and forgotten. Temporary credentials expire automatically.

### Least Privilege

Each component gets only the permissions it needs:

```hcl
# Task execution role - pull images, write logs
# Task role - application-specific (S3 access, etc.)
# Database - only accessible from ECS security group
```

**Why it matters:** If one component is compromised, the blast radius is limited.

### Signed Commits

All commits to infrastructure repositories should be cryptographically signed. This proves:
1. **Identity** — The commit actually came from who it claims
2. **Integrity** — The commit hasn't been tampered with
3. **Non-repudiation** — The author can't deny making the commit

**Why it matters for infrastructure:** A malicious actor who gains access to a developer's machine or GitHub account could push backdoored Terraform code. Signed commits make this significantly harder — they'd need to also compromise the signing key.

**Setup GPG signing (recommended):**

```bash
# 1. Generate a GPG key (if you don't have one)
gpg --full-generate-key
# Choose: RSA and RSA, 4096 bits, key does not expire
# Use your Git email address

# 2. Get your key ID
gpg --list-secret-keys --keyid-format=long
# Look for: sec   rsa4096/YOUR_KEY_ID

# 3. Configure Git to use it
git config --global user.signingkey YOUR_KEY_ID
git config --global commit.gpgsign true
git config --global tag.gpgsign true

# 4. Add to your shell profile (bash/zsh)
export GPG_TTY=$(tty)

# 5. Add public key to GitHub
gpg --armor --export YOUR_KEY_ID
# Copy output to: GitHub → Settings → SSH and GPG keys → New GPG key
```

**Alternative: SSH signing (simpler, Git 2.34+):**

```bash
# Use your existing SSH key for signing
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true

# Add SSH key to GitHub as a "signing key" (not just authentication)
# GitHub → Settings → SSH and GPG keys → New SSH key → Key type: Signing Key
```

**Verify it works:**

```bash
# Make a signed commit
git commit -S -m "test signed commit"

# Verify signature
git log --show-signature -1
```

**Enforcing in GitHub:**
- Repository Settings → Branches → Branch protection rules
- Enable "Require signed commits" for `main`

**References:**
- [GitHub: Signing commits](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits)
- [GitHub: SSH commit verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification#ssh-commit-signature-verification)
- [GPG best practices](https://riseup.net/en/security/message-security/openpgp/gpg-best-practices)

---

## Principle 4: Automated Verification

Trust, but verify — automatically.

### Pre-Commit Hooks

Before code even leaves your machine:

```yaml
# .pre-commit-config.yaml
- terraform_fmt      # Consistent formatting
- terraform_tflint   # Catch common mistakes
- checkov            # Security scanning
- detect-private-key # Catch accidental secrets
```

**Why it matters:** Catch problems before they enter the repository.

### Pull Request Validation

Every PR automatically runs:

1. **Format check** — Is the code formatted correctly?
2. **Linting** — Are there common mistakes?
3. **Validation** — Is the Terraform valid?
4. **Plan** — What would this change?

```yaml
# .github/workflows/terraform-validate.yml
- name: Terraform Format Check
  run: terraform fmt -check -recursive

- name: TFLint
  run: tflint --recursive

- name: Terraform Validate
  run: terraform validate
```

**Why it matters:** Broken code never reaches main branch.

### Staged Deployments

Changes flow: `dev → staging → prod`

```yaml
# .github/workflows/terraform-apply.yml
jobs:
  apply-dev:
    # Automatic

  apply-staging:
    needs: apply-dev  # Only after dev succeeds

  apply-prod:
    needs: apply-staging
    environment: production  # Requires manual approval
```

**Why it matters:** Problems are caught in dev/staging before reaching production.

---

## Principle 5: Cost Awareness

Cloud costs can spiral without visibility and controls.

### Budget Alerts

```hcl
# modules/aws/governance/main.tf
resource "aws_budgets_budget" "monthly" {
  budget_type  = "COST"
  limit_amount = var.monthly_budget_limit

  notification {
    threshold = 80  # Alert at 80% of budget
    # ...
  }
}
```

### Lifecycle Management

Resources are tagged as `temporary` or `persistent`:

```hcl
tags = {
  Lifecycle = "temporary"  # Will be cleaned up
}
```

A Lambda function scans for resources exceeding their lifecycle and can automatically terminate them.

**Why it matters:** Dev resources that run forever cost money. Automated cleanup prevents waste.

### Right-Sizing by Environment

```hcl
# Dev - minimal resources
db_instance_class = "db.t3.micro"
ecs_cpu          = 256
ecs_memory       = 512

# Prod - appropriate resources
db_instance_class = "db.t3.medium"
ecs_cpu          = 1024
ecs_memory       = 2048
```

**Why it matters:** Dev doesn't need production-sized resources. Save money where it doesn't matter.

---

## Principle 6: Local Development Parity

Production shouldn't be the first place you test.

### Docker Compose Mirror

```bash
# local/
docker compose up -d
```

This creates a local environment that mirrors production:

| Production | Local |
|------------|-------|
| ALB | Traefik |
| ECS | Docker containers |
| RDS | PostgreSQL container |
| Route53 | `.localhost` domains |

**Why it matters:** Test locally before deploying. Catch issues early.

### Same Patterns, Different Scale

Local and production use the same:
- Service configurations
- Environment variables
- Database schemas
- Authentication flows

Only the scale differs.

---

## How to Learn From This Repository

### Week 1: Understand the Structure

1. **Read this document completely**
2. **Explore the directory structure** — Understand the three layers
3. **Read `README.md`** — Project overview and setup
4. **Read `RECIPE.md`** — Architecture decisions

### Week 2: Trace a Module

Pick one module (start with `modules/aws/rds-postgres/`):

1. Read `main.tf` — What resources does it create?
2. Read `variables.tf` — What's configurable?
3. Read `outputs.tf` — What does it expose?
4. Find where it's used in `environments/aws/dev/main.tf`

### Week 3: Follow a Change

1. Look at Git history for a module
2. Find a pull request that modified it
3. See what CI/CD checks ran
4. Understand how it was reviewed and merged

### Week 4: Make a Change

1. Create a branch
2. Make a small change (add a tag, change a default)
3. Run pre-commit hooks locally
4. Open a pull request
5. Watch CI/CD run
6. Review the plan output

---

## Common Mistakes to Avoid

### ❌ Manual Changes

**Bad:** "I'll just update this in the console real quick"

**Why it's bad:**
- Next `terraform apply` will revert it
- No one knows it happened
- Can't reproduce it in other environments

**Good:** Make changes through Terraform and PRs

### ❌ Hardcoded Values

**Bad:**
```hcl
instance_type = "t3.medium"  # In production module
```

**Good:**
```hcl
instance_type = var.instance_type  # Configurable per environment
```

### ❌ Mega-Modules

**Bad:** One module that creates VPC + ECS + RDS + everything

**Good:** Small, focused modules that compose together

### ❌ Copy-Paste Environments

**Bad:** Copy the dev folder to create staging

**Good:** Same modules, different variables

### ❌ Skipping Reviews

**Bad:** Push directly to main

**Good:** Every change through a PR, every PR reviewed

---

## Building This Culture

Technical patterns are necessary but not sufficient. Culture makes them stick.

### Make It Easy

- Pre-commit hooks run automatically
- CI/CD doesn't require manual steps
- Templates and examples are provided
- Documentation is generated, not written

### Make It Expected

- PRs are required, not optional
- Reviews happen, not rubber-stamped
- Tests run, not skipped
- Costs are tracked, not ignored

### Make It Visible

- Dashboards show deployment status
- Alerts go to shared channels
- Costs are reported weekly
- Incidents are documented

### Make It Valuable

- Time saved by automation
- Incidents prevented by testing
- Money saved by cleanup
- Knowledge preserved in code

---

## The Compound Effect

These practices feel slow at first. Over time, they compound:

**Month 1:** "Why do I need a PR for this small change?"

**Month 6:** "I can understand changes from before I joined"

**Year 1:** "We deploy multiple times a day with confidence"

**Year 2:** "New team members are productive in their first week"

The goal isn't perfection on day one. The goal is a foundation that improves over time, where each problem solved makes the next problem easier.

---

## Summary

| Principle | Implementation | Why |
|-----------|----------------|-----|
| Idempotent IaC | Terraform, no manual changes | Reproducible, auditable |
| Housekeeping | Naming, tagging, docs | Maintainable, findable |
| Security | Network segregation, secrets management | Defense in depth |
| Automation | Pre-commit, CI/CD, staged deploys | Catch errors early |
| Cost awareness | Budgets, lifecycle, right-sizing | Fiscal responsibility |
| Local parity | Docker Compose mirror | Test before deploy |

**Remember:** The specific technologies (ECS, RDS, Terraform) can be swapped. The principles and discipline cannot.

Build infrastructure that your future self will thank you for.
