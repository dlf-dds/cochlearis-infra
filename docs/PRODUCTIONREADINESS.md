# Production Readiness Assessment

Assessment date: 2026-02-02

Target capacity: 100 concurrent users

## Service Status Summary

| Service | Status | Auth Method | HA Enabled | Notes |
|---------|--------|-------------|------------|-------|
| **BookStack** | READY | Azure AD / Google OAuth | Yes | Default admin: `admin@admin.com` / `password` |
| **Mattermost** | READY | Azure AD | Yes | First user becomes System Admin |
| **Outline** | READY | Slack OAuth | Yes | First user becomes admin |
| **Zulip** | READY | Azure AD / Google OAuth | Single EC2 | Running on EC2 (t3.medium) |
| **Docusaurus** | READY | ALB OIDC (optional) | Yes (ECS) | Static site, no persistent state |
| **Zitadel** | DEPLOYED (OIDC abandoned) | N/A | No | Identity provider - OIDC integration on hold |

---

## Infrastructure Configuration

### High Availability Settings (Applied)

```hcl
# BookStack, Mattermost, Outline
db_multi_az   = true   # RDS automatic failover
desired_count = 2      # Multiple ECS tasks across AZs
```

### Current Resource Sizing

| Service | Compute | Database | Cache |
|---------|---------|----------|-------|
| BookStack | 1 vCPU / 2GB RAM | db.t3.small (2GB) | N/A |
| Mattermost | 1 vCPU / 2GB RAM | db.t3.small (2GB) | N/A |
| Outline | 1 vCPU / 2GB RAM | db.t3.small (2GB) | cache.t3.small (1.5GB) |
| Zulip | t3.medium (2 vCPU / 4GB) | Local PostgreSQL | Local memcached |
| Zitadel | 0.5 vCPU / 1GB RAM | db.t3.micro (1GB) | N/A |

---

## Day 2 Operations

### Backups

| Service | Backup Method | Retention | Recovery |
|---------|---------------|-----------|----------|
| BookStack | RDS automated snapshots | 7 days | Restore from snapshot |
| Mattermost | RDS automated snapshots | 7 days | Restore from snapshot |
| Outline | RDS automated snapshots | 7 days | Restore from snapshot |
| Zulip | **MANUAL** - EC2 EBS snapshots | Configure manually | Restore from EBS snapshot |
| Zitadel | RDS automated snapshots | 7 days | Restore from snapshot |

**Action Required**: Configure automated EBS snapshots for Zulip EC2 instance.

```bash
# Create lifecycle policy for Zulip EBS snapshots
aws-vault exec cochlearis --no-session -- aws dlm create-lifecycle-policy \
  --description "Zulip daily snapshots" \
  --state ENABLED \
  --execution-role-arn arn:aws:iam::ACCOUNT_ID:role/AWSDataLifecycleManagerDefaultRole \
  --policy-details file://zulip-snapshot-policy.json
```

### Monitoring

**Current state**: Basic CloudWatch metrics only.

**Recommended additions**:
1. **CloudWatch Alarms** for:
   - ECS task failures (UnhealthyHostCount > 0)
   - RDS CPU > 80%
   - ALB 5xx errors > 5/minute
   - Zulip EC2 status checks

2. **Dashboards** for:
   - Service health overview
   - Response times per service
   - Database connections

```bash
# Check service health
aws-vault exec cochlearis --no-session -- aws ecs describe-services \
  --cluster cochlearis-dev-cluster \
  --services cochlearis-dev-bookstack cochlearis-dev-mattermost cochlearis-dev-outline \
  --region eu-central-1 \
  --query 'services[*].{name:serviceName,running:runningCount,desired:desiredCount}'
```

### Log Retention

Logs are stored in CloudWatch Logs:
- `/ecs/cochlearis-dev-bookstack`
- `/ecs/cochlearis-dev-mattermost`
- `/ecs/cochlearis-dev-outline`
- `/ecs/cochlearis-dev-zitadel`
- Zulip: `/var/log/` on EC2 instance

**Action Required**: Configure log retention policy (default is never expire).

```bash
aws-vault exec cochlearis --no-session -- aws logs put-retention-policy \
  --log-group-name /ecs/cochlearis-dev-bookstack \
  --retention-in-days 30 \
  --region eu-central-1
```

---

## Security Considerations

### Authentication

| Service | Self-Registration | Recommended Action |
|---------|-------------------|-------------------|
| BookStack | Disabled | Use OAuth only |
| Mattermost | Enabled (`enable_open_server = true`) | **Disable for production** |
| Outline | N/A (OAuth required) | Configure allowed email domains |
| Zulip | Enabled (`OPEN_REALM_CREATION = True`) | **Disable for production** |

**Production hardening**:
```hcl
# Mattermost - disable open signup
enable_open_server = false

# Outline - restrict email domains
allowed_domains = "yourdomain.com"
```

### Secrets Management

All secrets stored in AWS Secrets Manager:
- OAuth client secrets
- Database passwords
- SES SMTP credentials

**No hardcoded secrets in Terraform state** - all sensitive values use `sensitive = true`.

### Network Security

- All services in private subnets
- ALB is only public-facing component
- ECS tasks have no public IPs
- RDS databases not publicly accessible
- Zulip EC2 in private subnet, accessed via ALB

---

## Scaling Concerns

### Current Bottlenecks

1. **Zulip EC2**: Single instance, no auto-scaling
   - Risk: Single point of failure
   - Mitigation: Consider AWS Auto Scaling Group or managed Zulip

2. **Database connections**: t3.small RDS has ~87 max connections
   - At 100 users with connection pooling, should be adequate
   - Monitor `DatabaseConnections` CloudWatch metric

3. **ECS Fargate costs**: Running 2 tasks per service increases costs
   - ~$50/month additional per service for HA

### Scaling Recommendations

For growth beyond 100 users:

| Users | Database | ECS Tasks | Notes |
|-------|----------|-----------|-------|
| 100 | db.t3.small | 2 | Current config |
| 250 | db.t3.medium | 3 | Add connection monitoring |
| 500 | db.r6g.large | 4-6 | Consider read replicas |
| 1000+ | db.r6g.xlarge | 6+ | Add Redis cluster, CDN |

---

## Operational Runbook

### Restarting a Service

```bash
# Force new deployment (picks up latest task definition)
aws-vault exec cochlearis --no-session -- aws ecs update-service \
  --cluster cochlearis-dev-cluster \
  --service cochlearis-dev-bookstack \
  --force-new-deployment \
  --region eu-central-1
```

### Viewing Logs

```bash
# Tail recent logs
aws-vault exec cochlearis --no-session -- aws logs tail \
  /ecs/cochlearis-dev-bookstack \
  --region eu-central-1 \
  --follow

# Zulip logs (via SSM Session Manager)
aws-vault exec cochlearis --no-session -- aws ssm start-session \
  --target i-INSTANCE_ID \
  --region eu-central-1
# Then: tail -f /var/log/zulip/server.log
```

### Emergency Access

See [MANAGEMENT.md](MANAGEMENT.md) for service-specific admin access procedures.

| Service | Emergency Access |
|---------|-----------------|
| BookStack | Default admin: `admin@admin.com` / `password` |
| Mattermost | Create admin via `mmctl` |
| Outline | Update database `role = 'admin'` |
| Zulip | SSH to EC2, use `manage.py create_user` |
| Zitadel | Check Secrets Manager for admin password |

### Database Access

```bash
# Get RDS endpoint
aws-vault exec cochlearis --no-session -- aws rds describe-db-instances \
  --region eu-central-1 \
  --query 'DBInstances[*].{ID:DBInstanceIdentifier,Endpoint:Endpoint.Address}'

# Connect via bastion or SSM port forwarding
aws-vault exec cochlearis --no-session -- aws ssm start-session \
  --target i-INSTANCE_ID \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["RDS_ENDPOINT"],"portNumber":["5432"],"localPortNumber":["5432"]}'
```

---

## Cost Estimate

Monthly estimate with HA configuration:

| Component | Cost (USD/month) |
|-----------|-----------------|
| ALB (2x) | ~$35 |
| ECS Fargate (8 tasks) | ~$120 |
| RDS (4x db.t3.small Multi-AZ) | ~$120 |
| ElastiCache (1x cache.t3.small) | ~$25 |
| EC2 (1x t3.medium) | ~$30 |
| NAT Gateway | ~$35 |
| Data transfer | ~$20 |
| **Total** | **~$385/month** |

Note: Actual costs depend on usage patterns. Use AWS Cost Explorer for accurate tracking.

---

## Known Issues & Gotchas

See [GOTCHAS.md](GOTCHAS.md) for detailed troubleshooting. Key issues:

1. **ECS Deployment Timing**: Changes take 2-5 minutes after `terraform apply`
2. **Outline OAuth**: Requires Slack (or other OAuth) - no email/password login
3. **SES Sandbox**: Verify recipient emails until production access approved
4. **Zitadel OIDC**: Abandoned after 48 hours - use Azure AD/Google OAuth instead

---

## Pre-Production Checklist

- [ ] Run `terraform apply` to enable HA settings
- [ ] Verify all services healthy after HA deployment
- [ ] Configure Zulip EBS snapshot policy
- [ ] Set CloudWatch log retention policies
- [ ] Disable open registration (Mattermost, Zulip)
- [ ] Configure email domain restrictions
- [ ] Test OAuth sign-in for all services
- [ ] Document admin credentials in secure location
- [ ] Set up CloudWatch alarms for critical metrics
- [ ] Request SES production access (if needed)
- [ ] Review and approve monthly cost estimate
