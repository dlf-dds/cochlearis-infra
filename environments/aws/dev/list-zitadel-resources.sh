#!/bin/bash
# =============================================================================
# List Zitadel Resources for Terraform Import
# =============================================================================
#
# Lists projects and OIDC applications in Zitadel, outputting terraform import
# commands for redeployment scenarios where the database survived.
#
# Prerequisites:
#   - aws-vault configured with 'cochlearis' profile
#   - jq installed
#   - A Personal Access Token (PAT) from Zitadel
#
# Usage:
#   # Pass PAT as environment variable
#   ZITADEL_PAT="your-pat-here" ./list-zitadel-resources.sh
#
#   # Or the script will prompt for it
#   ./list-zitadel-resources.sh
#
# To create a PAT: See DEPLOY.md "Create Zitadel Service User" section
#
# =============================================================================

set -e

REGION="eu-central-1"
ZITADEL_URL="https://auth.dev.almondbread.org"
PROJECT="cochlearis"
ENVIRONMENT="dev"
AWS_CMD="aws-vault exec cochlearis --no-session -- aws"

echo "=== Zitadel Resource Lister ==="
echo ""

# Get PAT from environment or prompt
if [ -z "$ZITADEL_PAT" ]; then
    echo "No ZITADEL_PAT environment variable found."
    echo ""
    echo "To create a PAT:"
    echo "  1. Log into: ${ZITADEL_URL}/ui/console"
    echo "  2. Go to your service user (e.g., terraform-bootstrap)"
    echo "  3. Personal Access Tokens → +New → Copy token"
    echo ""
    read -p "Enter your Personal Access Token: " ZITADEL_PAT
    echo ""
fi

if [ -z "$ZITADEL_PAT" ]; then
    echo "ERROR: No PAT provided"
    exit 1
fi

ACCESS_TOKEN="$ZITADEL_PAT"

# Get organization ID from SSM (or from Zitadel API)
ORG_ID=$($AWS_CMD ssm get-parameter \
    --name "/${PROJECT}/${ENVIRONMENT}/zitadel/organization-id" \
    --region "$REGION" \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

if [ -z "$ORG_ID" ]; then
    echo "Fetching organization ID from Zitadel API..."
    ORG_RESPONSE=$(curl -s -X GET "${ZITADEL_URL}/management/v1/orgs/me" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json")
    ORG_ID=$(echo "$ORG_RESPONSE" | jq -r '.org.id')
fi

if [ -z "$ORG_ID" ] || [ "$ORG_ID" = "null" ]; then
    echo "ERROR: Could not determine organization ID"
    exit 1
fi

echo "Organization ID: $ORG_ID"
echo ""

# List projects
echo "=== Projects ==="
PROJECTS_RESPONSE=$(curl -s -X POST "${ZITADEL_URL}/management/v1/projects/_search" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${ORG_ID}" \
    -d '{}')

echo "$PROJECTS_RESPONSE" | jq -r '.result[]? | "Project: \(.name) (ID: \(.id))"'
echo ""

# Get project IDs
PROJECT_IDS=$(echo "$PROJECTS_RESPONSE" | jq -r '.result[]?.id // empty')

if [ -z "$PROJECT_IDS" ]; then
    echo "No projects found."
    exit 0
fi

# List applications for each project
echo "=== OIDC Applications ==="
for PROJECT_ID in $PROJECT_IDS; do
    PROJECT_NAME=$(echo "$PROJECTS_RESPONSE" | jq -r ".result[] | select(.id==\"$PROJECT_ID\") | .name")
    echo ""
    echo "Project: $PROJECT_NAME ($PROJECT_ID)"
    echo "---"

    APPS_RESPONSE=$(curl -s -X POST "${ZITADEL_URL}/management/v1/projects/${PROJECT_ID}/apps/_search" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -H "x-zitadel-orgid: ${ORG_ID}" \
        -d '{}')

    echo "$APPS_RESPONSE" | jq -r '.result[]? | "  App: \(.name) (ID: \(.id), ClientID: \(.oidcConfig.clientId // "N/A"))"'
done

echo ""
echo "=== Terraform Import Commands ==="
echo ""

# Generate import commands
for PROJECT_ID in $PROJECT_IDS; do
    PROJECT_NAME=$(echo "$PROJECTS_RESPONSE" | jq -r ".result[] | select(.id==\"$PROJECT_ID\") | .name")

    # Project import
    echo "# Import project: $PROJECT_NAME"
    echo "terraform import 'module.zitadel_oidc.zitadel_project.main' '$PROJECT_ID'"
    echo ""

    # Apps import
    APPS_RESPONSE=$(curl -s -X POST "${ZITADEL_URL}/management/v1/projects/${PROJECT_ID}/apps/_search" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -H "x-zitadel-orgid: ${ORG_ID}" \
        -d '{}')

    APP_DATA=$(echo "$APPS_RESPONSE" | jq -r '.result[]? | "\(.name)|\(.id)"')

    for APP in $APP_DATA; do
        APP_NAME=$(echo "$APP" | cut -d'|' -f1)
        APP_ID=$(echo "$APP" | cut -d'|' -f2)

        # Map app name to terraform resource name
        case "$APP_NAME" in
            "BookStack") RESOURCE_NAME="bookstack" ;;
            "Mattermost") RESOURCE_NAME="mattermost" ;;
            "Zulip") RESOURCE_NAME="zulip" ;;
            "Outline") RESOURCE_NAME="outline[0]" ;;
            *) RESOURCE_NAME=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]') ;;
        esac

        echo "# Import app: $APP_NAME"
        echo "terraform import 'module.zitadel_oidc.zitadel_application_oidc.${RESOURCE_NAME}' '${APP_ID}:${PROJECT_ID}'"
        echo ""
    done
done

echo "=== Done ==="
