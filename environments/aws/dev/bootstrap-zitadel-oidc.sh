#!/bin/bash
# =============================================================================
# Bootstrap Zitadel Service Account for Terraform OIDC Management
# =============================================================================
#
# This script creates a service account in Zitadel with IAM_OWNER permissions
# and stores the JWT key in AWS Secrets Manager for use by Terraform.
#
# Prerequisites:
#   - Zitadel must be running and accessible
#   - You must create a Personal Access Token (PAT) in the Zitadel console
#   - aws-vault configured with 'cochlearis' profile
#   - jq installed
#
# Usage:
#   # Option 1: Pass PAT as environment variable
#   ZITADEL_PAT="your-pat-here" ./bootstrap-zitadel-oidc.sh
#
#   # Option 2: Script will prompt for PAT
#   ./bootstrap-zitadel-oidc.sh
#
# To create a PAT (PATs are only for service/machine users, not human users):
#   1. Log into Zitadel console: https://auth.dev.almondbread.org/ui/console
#   2. Username: admin@zitadel.auth.dev.almondbread.org
#   3. Password: (from Secrets Manager - see command below)
#   4. Left sidebar -> Organization -> Service Users -> +New
#   5. Create user "terraform-bootstrap", grant ORG_OWNER role
#   6. Click the user -> scroll to "Personal Access Tokens" -> +New
#   7. Copy the token (won't be shown again)
#
# To get admin password:
#   aws-vault exec cochlearis --no-session -- aws secretsmanager get-secret-value \
#     --secret-id cochlearis-dev-zitadel-master-key --region eu-central-1 \
#     --query 'SecretString' --output text | jq -r '.admin_password'
#
# After running this script:
#   1. Set enable_zitadel_oidc = true in terraform.tfvars
#   2. Run terraform apply
# =============================================================================

set -e

REGION="eu-central-1"
DOMAIN="almondbread.org"
ZITADEL_URL="https://auth.dev.$DOMAIN"
PROJECT="cochlearis"
ENVIRONMENT="dev"
SECRET_NAME="${PROJECT}-${ENVIRONMENT}-zitadel-service-account"
AWS_CMD="aws-vault exec cochlearis --no-session -- aws"

echo "=== Zitadel OIDC Bootstrap ==="
echo ""
echo "This script will:"
echo "  1. Use your Personal Access Token to authenticate"
echo "  2. Create a service account for Terraform"
echo "  3. Store the service account key in AWS Secrets Manager"
echo ""

# Get PAT from environment or prompt
if [ -z "$ZITADEL_PAT" ]; then
    echo "No ZITADEL_PAT environment variable found."
    echo ""
    echo "PATs in Zitadel are only for SERVICE USERS (machine users), not human users."
    echo ""
    echo "To create a PAT:"
    echo "  1. Log into: ${ZITADEL_URL}/ui/console"
    echo "  2. Username: admin@zitadel.auth.dev.${DOMAIN}"
    echo "  3. Left sidebar -> Organization -> Service Users -> +New"
    echo "  4. Create user 'terraform-bootstrap', grant ORG_OWNER role"
    echo "  5. Click the user -> scroll to 'Personal Access Tokens' -> +New"
    echo "  6. Copy the token (won't be shown again)"
    echo ""
    echo "To get admin password:"
    echo "  $AWS_CMD secretsmanager get-secret-value \\"
    echo "    --secret-id ${PROJECT}-${ENVIRONMENT}-zitadel-master-key --region $REGION \\"
    echo "    --query 'SecretString' --output text | jq -r '.admin_password'"
    echo ""
    read -p "Enter your Personal Access Token: " ZITADEL_PAT
    echo ""
fi

if [ -z "$ZITADEL_PAT" ]; then
    echo "ERROR: No PAT provided"
    exit 1
fi

ACCESS_TOKEN="$ZITADEL_PAT"

# Verify token works by getting organization info
echo "Verifying token and fetching organization ID..."
ORG_RESPONSE=$(curl -s -X GET "${ZITADEL_URL}/management/v1/orgs/me" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json")

ORG_ID=$(echo "$ORG_RESPONSE" | jq -r '.org.id')

if [ -z "$ORG_ID" ] || [ "$ORG_ID" = "null" ]; then
    echo "ERROR: Could not fetch organization ID - token may be invalid"
    echo "Response: $ORG_RESPONSE"
    exit 1
fi

echo "Successfully authenticated!"
echo "Organization ID: $ORG_ID"

# Check if service account already exists
echo "Checking for existing service account..."
EXISTING_USER=$(curl -s -X POST "${ZITADEL_URL}/management/v1/users/_search" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${ORG_ID}" \
    -d '{"queries": [{"typeQuery": {"type": "TYPE_MACHINE"}}, {"userNameQuery": {"userName": "terraform-oidc"}}]}')

EXISTING_USER_ID=$(echo "$EXISTING_USER" | jq -r '.result[0].id // empty')

if [ -n "$EXISTING_USER_ID" ]; then
    echo "Service account already exists with ID: $EXISTING_USER_ID"
    USER_ID=$EXISTING_USER_ID
else
    # Create service account (machine user)
    echo "Creating service account..."
    CREATE_RESPONSE=$(curl -s -X POST "${ZITADEL_URL}/management/v1/users/machine" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -H "x-zitadel-orgid: ${ORG_ID}" \
        -d '{
            "userName": "terraform-oidc",
            "name": "Terraform OIDC Manager",
            "description": "Service account for managing OIDC applications via Terraform",
            "accessTokenType": "ACCESS_TOKEN_TYPE_JWT"
        }')

    USER_ID=$(echo "$CREATE_RESPONSE" | jq -r '.userId')

    if [ -z "$USER_ID" ] || [ "$USER_ID" = "null" ]; then
        echo "ERROR: Could not create service account"
        echo "Response: $CREATE_RESPONSE"
        exit 1
    fi

    echo "Created service account with ID: $USER_ID"
fi

# Grant IAM_OWNER role to the service account
echo "Granting IAM_OWNER role..."
GRANT_RESPONSE=$(curl -s -X POST "${ZITADEL_URL}/management/v1/orgs/me/members" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${ORG_ID}" \
    -d "{
        \"userId\": \"${USER_ID}\",
        \"roles\": [\"ORG_OWNER\"]
    }")

# Also grant IAM admin permissions
GRANT_IAM_RESPONSE=$(curl -s -X POST "${ZITADEL_URL}/admin/v1/members" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
        \"userId\": \"${USER_ID}\",
        \"roles\": [\"IAM_OWNER\"]
    }")

echo "Permissions granted"

# Generate a new key for the service account
echo "Generating service account key..."
KEY_RESPONSE=$(curl -s -X POST "${ZITADEL_URL}/management/v1/users/${USER_ID}/keys" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${ORG_ID}" \
    -d '{
        "type": "KEY_TYPE_JSON",
        "expirationDate": "2030-01-01T00:00:00Z"
    }')

KEY_DETAILS=$(echo "$KEY_RESPONSE" | jq -r '.keyDetails')

if [ -z "$KEY_DETAILS" ] || [ "$KEY_DETAILS" = "null" ]; then
    echo "ERROR: Could not generate service account key"
    echo "Response: $KEY_RESPONSE"
    exit 1
fi

# Decode the key (it's base64 encoded)
SERVICE_ACCOUNT_KEY=$(echo "$KEY_DETAILS" | base64 -d 2>/dev/null || echo "$KEY_DETAILS" | base64 -D 2>/dev/null)

echo "Service account key generated"

# Store the key in AWS Secrets Manager
echo "Storing key in AWS Secrets Manager..."

# Check if secret already exists
SECRET_EXISTS=$($AWS_CMD secretsmanager describe-secret \
    --secret-id "$SECRET_NAME" \
    --region "$REGION" 2>/dev/null || echo "")

if [ -n "$SECRET_EXISTS" ]; then
    # Update existing secret
    $AWS_CMD secretsmanager put-secret-value \
        --secret-id "$SECRET_NAME" \
        --secret-string "$SERVICE_ACCOUNT_KEY" \
        --region "$REGION" > /dev/null
    echo "Updated existing secret: $SECRET_NAME"
else
    # Create new secret
    $AWS_CMD secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "Zitadel service account key for Terraform OIDC management" \
        --secret-string "$SERVICE_ACCOUNT_KEY" \
        --region "$REGION" > /dev/null
    echo "Created new secret: $SECRET_NAME"
fi

# Store organization ID in SSM Parameter Store for Terraform to read
echo "Storing organization ID in SSM Parameter Store..."
PARAM_NAME="/${PROJECT}/${ENVIRONMENT}/zitadel/organization-id"

$AWS_CMD ssm put-parameter \
    --name "$PARAM_NAME" \
    --value "$ORG_ID" \
    --type "String" \
    --overwrite \
    --region "$REGION" > /dev/null

echo "Stored organization ID in: $PARAM_NAME"

echo ""
echo "=== Bootstrap Complete ==="
echo ""
echo "Service Account ID: $USER_ID"
echo "Organization ID:    $ORG_ID"
echo ""
echo "Next steps:"
echo "  1. Set enable_zitadel_oidc = true in terraform.tfvars"
echo "  2. Run: terraform apply"
echo ""
echo "Terraform will automatically read the organization ID from SSM."
