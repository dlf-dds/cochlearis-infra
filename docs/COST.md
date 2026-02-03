# Cost Analysis - Cochlearis Infrastructure

This document details all AWS resources deployed for the Almondbread Collaboration Services platform, their sizing rationale, and estimated monthly costs.

**Target capacity:** ~100 concurrent users over a 2-week intensive work period.

---

## Resource Summary

### Current Configuration (eu-central-1)

| Category | Resource | Count | Spec | Monthly Est. |
|----------|----------|-------|------|--------------|
| **Compute (ECS Fargate)** | | | | |
| | Zulip + PostgreSQL sidecar | 1 | 2 vCPU / 4GB | ~$73 |
| | Zulip Mini (troubleshooting) | 1 | 2 vCPU / 4GB | ~$73 |
| | BookStack | 1 | 1 vCPU / 2GB | ~$36 |
| | Mattermost | 1 | 1 vCPU / 2GB | ~$36 |
| | Outline | 1 | 1 vCPU / 2GB | ~$36 |
| | Zitadel | 1 | 0.5 vCPU / 1GB | ~$18 |
| | Docusaurus | 1 | 0.25 vCPU / 0.5GB | ~$9 |
| **Databases (RDS)** | | | | |
| | BookStack (MySQL) | 1 | db.t3.small | ~$25 |
| | Mattermost (PostgreSQL) | 1 | db.t3.small | ~$25 |
| | Outline (PostgreSQL) | 1 | db.t3.small | ~$25 |
| | Zitadel (PostgreSQL) | 1 | db.t3.micro | ~$13 |
| **Caching (ElastiCache)** | | | | |
| | Zulip Redis | 1 | cache.t3.small | ~$25 |
| | Outline Redis | 1 | cache.t3.small | ~$25 |
| **Storage** | | | | |
| | Zulip EFS | 1 | Pay-per-use | ~$5-15 |
| | Outline S3 | 1 | Pay-per-use | ~$1-5 |
| | ECR (container images) | 6 repos | Pay-per-use | ~$2-5 |
| **Networking** | | | | |
| | ALB (public) | 1 | Fixed + LCU | ~$22 |
| | ALB (internal) | 1 | Fixed + LCU | ~$22 |
| | NAT Gateway | 3 (per-AZ) | Fixed + data | ~$100 |
| | VPC Endpoints | 4 | Fixed | ~$30 |
| **DNS & Certificates** | | | | |
| | Route 53 hosted zone | 1 | Fixed | ~$0.50 |
| | Route 53 queries | - | Pay-per-use | ~$1-2 |
| | ACM certificates | 7 | Free | $0 |
| **Secrets & Config** | | | | |
| | Secrets Manager | ~15 secrets | Fixed | ~$6 |
| | SSM Parameter Store | ~10 params | Free tier | $0 |
| **Governance** | | | | |
| | SNS Topic | 1 | Free tier | $0 |
| | CloudWatch (logs, alarms) | - | Pay-per-use | ~$5-10 |

**Estimated Total: ~$600-700/month**

---

## Detailed Justifications

### ECS Fargate Compute

**Why Fargate over EC2?**
- No instance management, patching, or capacity planning
- Pay-per-second billing — no wasted capacity when idle
- Simpler `terraform destroy` — no orphaned EC2 instances
- Scales to zero if services are stopped

**Sizing rationale:**

| Service | CPU | Memory | Why |
|---------|-----|--------|-----|
| **Zulip** | 2048 (2 vCPU) | 4096 MB | PostgreSQL sidecar + Python app + Tornado async workers |
| **Zulip Mini** | 2048 (2 vCPU) | 4096 MB | All-in-one includes internal PostgreSQL + Redis |
| **BookStack** | 1024 (1 vCPU) | 2048 MB | PHP app, 100 users editing docs concurrently |
| **Mattermost** | 1024 (1 vCPU) | 2048 MB | Go app, real-time WebSocket connections |
| **Outline** | 1024 (1 vCPU) | 2048 MB | Node.js, real-time collaboration |
| **Zitadel** | 512 (0.5 vCPU) | 1024 MB | Identity provider, lower load (auth events only) |
| **Docusaurus** | 256 (0.25 vCPU) | 512 MB | Static content, nginx serving files |

### RDS Databases

**Why t3.small over t3.micro?**
- **t3.micro**: 1GB RAM, 2 vCPUs (burstable), limited IOPS
- **t3.small**: 2GB RAM, 2 vCPUs (burstable), better sustained performance

The `t3.micro` CPU credits deplete under sustained load from 100 users. Once depleted, performance drops to baseline (~10% of capacity), causing timeouts.

| Database | Instance | Storage | Why |
|----------|----------|---------|-----|
| BookStack | db.t3.small | 20GB gp3 | Wiki with attachments, search indexes |
| Mattermost | db.t3.small | 20GB gp3 | Message history, file metadata |
| Outline | db.t3.small | 20GB gp3 | Documents, revisions, search |
| Zitadel | db.t3.micro | 20GB gp3 | Identity events (lower volume than apps) |

**Why single-AZ?**
- Multi-AZ doubles RDS cost
- For a 2-week event, single-AZ is acceptable risk
- Can enable Multi-AZ for production

### ElastiCache Redis

**Why cache.t3.small over cache.t3.micro?**
- **t3.micro**: 0.5GB memory — will OOM with 100 concurrent sessions
- **t3.small**: 1.5GB memory — comfortable headroom for sessions + cache

| Cache | Instance | Why |
|-------|----------|-----|
| Zulip Redis | cache.t3.small | Session storage, message queue, presence |
| Outline Redis | cache.t3.small | Session storage, document locks, cache |

### Storage

**EFS (Zulip PostgreSQL data)**
- Zulip uses a PostgreSQL sidecar instead of RDS to avoid major version upgrade limitations
- EFS provides persistent storage across task restarts
- ~$0.30/GB-month, expect 5-20GB for a 2-week event

**S3 (Outline uploads)**
- User-uploaded files, images, attachments
- Pay-per-use, typically <$5/month unless heavy file sharing

**ECR (Container images)**
- Mirrors Docker Hub images to avoid 429 rate limits
- 6 repositories × ~500MB each = ~3GB
- ~$0.10/GB-month = ~$0.30/month for storage
- Pull costs are negligible with VPC endpoints

### Networking

**VPC Structure:**
```
VPC: 10.0.0.0/16
├── Public Subnets (3 AZs): 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24
│   └── ALB (public), NAT Gateways
└── Private Subnets (3 AZs): 10.0.11.0/24, 10.0.12.0/24, 10.0.13.0/24
    └── ECS tasks, RDS, ElastiCache
```

**Why 3 NAT Gateways?**
- One per AZ for high availability
- If one AZ fails, other AZs continue to function
- Cost: ~$32/month each + $0.045/GB data processing
- **Alternative:** Single NAT Gateway saves ~$65/month but risks AZ failure

**Why 2 ALBs?**
1. **Public ALB**: Internet-facing, routes user traffic to services
2. **Internal ALB**: Private, solves hairpin NAT for service-to-service OIDC

The internal ALB exists because ECS tasks in private subnets cannot route to their own public ALB IP. When BookStack calls `auth.dev.almondbread.org/.well-known/openid-configuration`, it needs to resolve to an internal IP.

**VPC Endpoints:**
| Endpoint | Type | Why |
|----------|------|-----|
| ECR API | Interface | Pull container images without NAT |
| ECR DKR | Interface | Docker registry protocol |
| S3 | Gateway | Outline uploads, ECS logs (free) |
| Secrets Manager | Interface | Fetch secrets without NAT |

Interface endpoints cost ~$7.50/month each. The S3 gateway endpoint is free.

### DNS & Certificates

**Route 53:**
- Public hosted zone: `almondbread.org`
- Private hosted zone: `dev.almondbread.org` (VPC-internal)
- ~$0.50/month + $0.40 per million queries

**ACM Certificates (free):**
- One wildcard cert per domain would be simpler, but we use per-service certs
- `auth.dev.almondbread.org`, `docs.dev.almondbread.org`, etc.

### Secrets Management

**Secrets Manager:** ~$0.40/secret/month
- Database credentials (4)
- OAuth client secrets (2-3)
- App-specific secrets (OIDC, API keys)

---

## Cost Optimization Options

### Immediate Savings (Low Risk)

| Change | Savings | Trade-off |
|--------|---------|-----------|
| Single NAT Gateway | ~$65/month | Single point of failure |
| Remove Zulip Mini | ~$75/month | Lose troubleshooting instance |
| Spot Fargate (where supported) | ~20% compute | Potential interruptions |

### Post-Event Savings

| Change | Savings | Trade-off |
|--------|---------|-----------|
| Scale to t3.micro | ~$50/month | Only works for <20 users |
| Remove redundant chat (Mattermost or Zulip) | ~$85/month | Consolidation decision |
| Stop non-essential services | Variable | Manual restart needed |

### Production Upgrades (More Cost)

| Change | Additional Cost | Benefit |
|--------|-----------------|---------|
| Multi-AZ RDS | +$75/month | Database HA |
| Reserved Instances (1yr) | - | ~30% savings on RDS |
| Fargate Savings Plans | - | ~20% savings on compute |

---

## Monitoring Costs

Use AWS Cost Explorer to track actual spend by:
- Service (ECS, RDS, ElastiCache, etc.)
- Tag (`Project=cochlearis`, `Environment=dev`)

The governance module creates budget alerts at 50%, 80%, 100%, and 120% of the configured `monthly_budget_limit`.

---

## Comparison: Dev vs Production

| Resource | Dev (current) | Production (recommended) |
|----------|---------------|--------------------------|
| RDS | db.t3.small, single-AZ | db.t3.medium+, multi-AZ |
| ElastiCache | cache.t3.small | cache.t3.medium+, multi-AZ |
| ECS | Single task per service | 2+ tasks with autoscaling |
| NAT Gateway | 3 (one per AZ) | 3 (required for HA) |
| Deletion protection | Disabled | Enabled |
| Backups | Minimal retention | 7-30 day retention |

**Estimated Production Cost:** ~$1,200-1,500/month
