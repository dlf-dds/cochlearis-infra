#!/bin/bash
# =============================================================================
# Outline Database Initialization Script
# =============================================================================
# Run this ONCE after deploying Outline for the first time.
# It creates the initial team and authentication providers needed for
# personal Google/Azure accounts to log in.
#
# Usage: ./init-outline.sh [team_name]
#
# Prerequisites:
# - aws-vault configured with 'cochlearis' profile
# - Zulip EC2 instance running (used as bastion for RDS access)
# - postgresql-client installed on Zulip EC2 (script will install if missing)

set -e

TEAM_NAME="${1:-Cochlearis}"
REGION="eu-central-1"
CLUSTER="cochlearis-dev-cluster"

echo "=== Outline Database Initialization ==="
echo "Team name: $TEAM_NAME"
echo ""

# Get database connection details from Secrets Manager
echo "Fetching database credentials..."
SECRET_NAME=$(aws-vault exec cochlearis --no-session -- aws secretsmanager list-secrets \
  --region $REGION \
  --query 'SecretList[?contains(Name, `outline`) && contains(Name, `master-password`)].Name' \
  --output text)

if [ -z "$SECRET_NAME" ]; then
  echo "ERROR: Could not find Outline database secret"
  exit 1
fi

DB_CREDS=$(aws-vault exec cochlearis --no-session -- aws secretsmanager get-secret-value \
  --region $REGION \
  --secret-id "$SECRET_NAME" \
  --query 'SecretString' \
  --output text)

DB_HOST=$(echo "$DB_CREDS" | jq -r '.host')
DB_PORT=$(echo "$DB_CREDS" | jq -r '.port')
DB_USER=$(echo "$DB_CREDS" | jq -r '.username')
DB_PASS=$(echo "$DB_CREDS" | jq -r '.password')
DB_NAME=$(echo "$DB_CREDS" | jq -r '.database')

echo "Database: $DB_HOST:$DB_PORT/$DB_NAME"

# Get Zulip EC2 instance ID (used as bastion)
ZULIP_INSTANCE=$(aws-vault exec cochlearis --no-session -- aws ec2 describe-instances \
  --region $REGION \
  --filters "Name=tag:Name,Values=*zulip*" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

if [ "$ZULIP_INSTANCE" == "None" ] || [ -z "$ZULIP_INSTANCE" ]; then
  echo "ERROR: Could not find running Zulip EC2 instance"
  exit 1
fi

echo "Using Zulip EC2 instance as bastion: $ZULIP_INSTANCE"

# Get Zulip security group
ZULIP_SG=$(aws-vault exec cochlearis --no-session -- aws ec2 describe-instances \
  --region $REGION \
  --instance-ids "$ZULIP_INSTANCE" \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
  --output text)

# Get Outline RDS security group
OUTLINE_RDS_SG=$(aws-vault exec cochlearis --no-session -- aws rds describe-db-instances \
  --region $REGION \
  --db-instance-identifier cochlearis-dev-outline \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)

echo "Adding temporary security group rule..."
SG_RULE_ID=$(aws-vault exec cochlearis --no-session -- aws ec2 authorize-security-group-ingress \
  --region $REGION \
  --group-id "$OUTLINE_RDS_SG" \
  --protocol tcp \
  --port 5432 \
  --source-group "$ZULIP_SG" \
  --query 'SecurityGroupRules[0].SecurityGroupRuleId' \
  --output text 2>/dev/null || echo "")

if [ -z "$SG_RULE_ID" ]; then
  echo "Security group rule may already exist, continuing..."
fi

# Get Outline domain from terraform outputs
OUTLINE_DOMAIN="wiki.dev.almondbread.org"

# SQL to initialize database
SQL_COMMANDS=$(cat <<EOF
-- Install pgcrypto extension if needed for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Check if team exists
DO \\\$\\\$
DECLARE
  team_id UUID;
  provider_exists BOOLEAN;
BEGIN
  -- Get or create team
  SELECT id INTO team_id FROM teams LIMIT 1;

  IF team_id IS NULL THEN
    INSERT INTO teams (id, name, domain, "createdAt", "updatedAt")
    VALUES (gen_random_uuid(), '$TEAM_NAME', '$OUTLINE_DOMAIN', NOW(), NOW())
    RETURNING id INTO team_id;
    RAISE NOTICE 'Created team: %', team_id;
  ELSE
    -- Update domain if not set
    UPDATE teams SET domain = '$OUTLINE_DOMAIN'
    WHERE id = team_id AND (domain IS NULL OR domain = '');
    RAISE NOTICE 'Using existing team: %', team_id;
  END IF;

  -- Create Google auth provider if not exists
  SELECT EXISTS(SELECT 1 FROM authentication_providers WHERE "providerId" = 'google' AND "teamId" = team_id) INTO provider_exists;
  IF NOT provider_exists THEN
    INSERT INTO authentication_providers (id, name, "providerId", enabled, "teamId", "createdAt")
    VALUES (gen_random_uuid(), 'Google', 'google', true, team_id, NOW());
    RAISE NOTICE 'Created Google auth provider';
  END IF;

  -- Create Azure auth provider if not exists
  SELECT EXISTS(SELECT 1 FROM authentication_providers WHERE "providerId" = 'azure' AND "teamId" = team_id) INTO provider_exists;
  IF NOT provider_exists THEN
    INSERT INTO authentication_providers (id, name, "providerId", enabled, "teamId", "createdAt")
    VALUES (gen_random_uuid(), 'Azure', 'azure', true, team_id, NOW());
    RAISE NOTICE 'Created Azure auth provider';
  END IF;
END\\\$\\\$;

-- Verify results
SELECT 'Teams:' as info;
SELECT id, name, domain FROM teams;
SELECT 'Auth Providers:' as info;
SELECT id, name, "providerId", enabled FROM authentication_providers;
EOF
)

echo ""
echo "Running database initialization..."

# Run SQL via SSM
CMD_ID=$(aws-vault exec cochlearis --no-session -- aws ssm send-command \
  --region $REGION \
  --instance-ids "$ZULIP_INSTANCE" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[
    \"sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql-client > /dev/null 2>&1 || true\",
    \"PGPASSWORD='$DB_PASS' psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c \\\"$SQL_COMMANDS\\\" 2>&1\"
  ]" \
  --query 'Command.CommandId' \
  --output text)

echo "SSM Command ID: $CMD_ID"
echo "Waiting for command to complete..."

# Wait for command to complete
sleep 30

# Get command result
RESULT=$(aws-vault exec cochlearis --no-session -- aws ssm get-command-invocation \
  --region $REGION \
  --command-id "$CMD_ID" \
  --instance-id "$ZULIP_INSTANCE" \
  --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}' \
  --output json)

STATUS=$(echo "$RESULT" | jq -r '.Status')
OUTPUT=$(echo "$RESULT" | jq -r '.Output')
ERROR=$(echo "$RESULT" | jq -r '.Error')

echo ""
echo "=== Result ==="
echo "Status: $STATUS"
echo ""
echo "Output:"
echo "$OUTPUT"

if [ -n "$ERROR" ] && [ "$ERROR" != "" ]; then
  echo ""
  echo "Errors:"
  echo "$ERROR"
fi

# Clean up security group rule
if [ -n "$SG_RULE_ID" ]; then
  echo ""
  echo "Removing temporary security group rule..."
  aws-vault exec cochlearis --no-session -- aws ec2 revoke-security-group-ingress \
    --region $REGION \
    --group-id "$OUTLINE_RDS_SG" \
    --security-group-rule-ids "$SG_RULE_ID" > /dev/null 2>&1 || true
fi

echo ""
echo "=== Done ==="
echo "Outline should now accept personal Google/Azure accounts."
echo "URL: https://$OUTLINE_DOMAIN"
