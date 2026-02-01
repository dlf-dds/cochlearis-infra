#!/bin/bash
# Import script - continues on errors

# Helper function to import if resource exists
import_resource() {
    local resource_addr="$1"
    local resource_id="$2"
    echo "Importing $resource_addr..."
    if terraform import "$resource_addr" "$resource_id" 2>&1; then
        echo "  ✓ Imported successfully"
    else
        echo "  ✗ Import failed (resource may not exist or already imported)"
    fi
}

# Target Groups
echo ""
echo "=== Target Groups ==="
for svc in zulip bookstack zitadel; do
    TG_NAME="cochlearis-dev-${svc}"
    TG_ARN=$(aws elbv2 describe-target-groups --names "$TG_NAME" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")
    if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
        import_resource "module.${svc}.module.service.aws_lb_target_group.main[0]" "$TG_ARN"
    else
        echo "  Target group $TG_NAME does not exist, skipping"
    fi
done

# ElastiCache Subnet Group
echo ""
echo "=== ElastiCache Subnet Group ==="
REDIS_SUBNET="cochlearis-dev-zulip-redis-subnet"
if aws elasticache describe-cache-subnet-groups --cache-subnet-group-name "$REDIS_SUBNET" 2>/dev/null >/dev/null; then
    import_resource 'module.zulip.module.redis.aws_elasticache_subnet_group.main' "$REDIS_SUBNET"
else
    echo "  Subnet group $REDIS_SUBNET does not exist, skipping"
fi

# Security Groups
echo ""
echo "=== Security Groups ==="
SG_NAMES=("cochlearis-dev-zulip-redis-sg" "cochlearis-dev-bookstack-mysql-sg" "cochlearis-dev-zulip-rds-sg" "cochlearis-dev-zitadel-rds-sg")
SG_ADDRS=("module.zulip.module.redis.aws_security_group.redis" "module.bookstack.module.database.aws_security_group.rds" "module.zulip.module.database.aws_security_group.rds" "module.zitadel.module.database.aws_security_group.rds")

for i in "${!SG_NAMES[@]}"; do
    sg_name="${SG_NAMES[$i]}"
    sg_addr="${SG_ADDRS[$i]}"
    SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$sg_name" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
    if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
        import_resource "$sg_addr" "$SG_ID"
    else
        echo "  Security group $sg_name does not exist, skipping"
    fi
done

# DB Subnet Groups
echo ""
echo "=== DB Subnet Groups ==="
DB_SUBNET_NAMES=("cochlearis-dev-bookstack-mysql-subnet" "cochlearis-dev-zitadel-db-subnet" "cochlearis-dev-zulip-db-subnet")
DB_SUBNET_ADDRS=("module.bookstack.module.database.aws_db_subnet_group.main" "module.zitadel.module.database.aws_db_subnet_group.main" "module.zulip.module.database.aws_db_subnet_group.main")

for i in "${!DB_SUBNET_NAMES[@]}"; do
    subnet_name="${DB_SUBNET_NAMES[$i]}"
    subnet_addr="${DB_SUBNET_ADDRS[$i]}"
    if aws rds describe-db-subnet-groups --db-subnet-group-name "$subnet_name" 2>/dev/null >/dev/null; then
        import_resource "$subnet_addr" "$subnet_name"
    else
        echo "  DB subnet group $subnet_name does not exist, skipping"
    fi
done

# Secrets Manager Secrets
echo ""
echo "=== Secrets Manager Secrets ==="
SECRET_NAMES=("cochlearis-dev-mysql-bookstack-master-password" "cochlearis-dev-rds-zulip-master-password" "cochlearis-dev-rds-zitadel-master-password" "cochlearis-dev-bookstack-app-key" "cochlearis-dev-zitadel-master-key" "cochlearis-dev-zulip-secrets")
SECRET_ADDRS=("module.bookstack.module.database.aws_secretsmanager_secret.master_password" "module.zulip.module.database.aws_secretsmanager_secret.master_password" "module.zitadel.module.database.aws_secretsmanager_secret.master_password" "module.bookstack.aws_secretsmanager_secret.app_key" "module.zitadel.aws_secretsmanager_secret.master_key" "module.zulip.aws_secretsmanager_secret.secrets")

for i in "${!SECRET_NAMES[@]}"; do
    secret_name="${SECRET_NAMES[$i]}"
    secret_addr="${SECRET_ADDRS[$i]}"
    SECRET_ARN=$(aws secretsmanager describe-secret --secret-id "$secret_name" --query 'ARN' --output text 2>/dev/null || echo "")
    if [ -n "$SECRET_ARN" ] && [ "$SECRET_ARN" != "None" ]; then
        import_resource "$secret_addr" "$SECRET_ARN"
    else
        echo "  Secret $secret_name does not exist, skipping"
    fi
done

# IAM User
echo ""
echo "=== IAM User ==="
IAM_USER="cochlearis-dev-zulip-ses"
if aws iam get-user --user-name "$IAM_USER" 2>/dev/null >/dev/null; then
    import_resource 'module.zulip.module.ses_user.aws_iam_user.main' "$IAM_USER"
else
    echo "  IAM user $IAM_USER does not exist, skipping"
fi

# S3 Buckets
echo ""
echo "=== S3 Buckets ==="
if aws s3api head-bucket --bucket "cochlearis-dev-bookstack-uploads" 2>/dev/null; then
    import_resource 'module.bookstack.aws_s3_bucket.uploads' 'cochlearis-dev-bookstack-uploads'
else
    echo "  S3 bucket cochlearis-dev-bookstack-uploads does not exist, skipping"
fi

if aws s3api head-bucket --bucket "cochlearis-dev-zulip-uploads" 2>/dev/null; then
    import_resource 'module.zulip.aws_s3_bucket.uploads' 'cochlearis-dev-zulip-uploads'
else
    echo "  S3 bucket cochlearis-dev-zulip-uploads does not exist, skipping"
fi

# Security Group Rules
echo ""
echo "=== Security Group Rules ==="
ECS_TASKS_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=cochlearis-dev-ecs-tasks-sg" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
ALB_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=cochlearis-dev-alb-sg" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")

if [ -n "$ECS_TASKS_SG" ] && [ -n "$ALB_SG" ] && [ "$ECS_TASKS_SG" != "None" ] && [ "$ALB_SG" != "None" ]; then
    # Import format: sg-id_type_protocol_from-port_to-port_source-sg
    import_resource "module.zulip.aws_security_group_rule.alb_to_ecs" "${ECS_TASKS_SG}_ingress_tcp_80_80_${ALB_SG}"
else
    echo "  Required security groups not found, skipping SG rule import"
fi

echo ""
echo "=== Import complete! ==="
echo "Run 'terraform plan' to see remaining changes."
