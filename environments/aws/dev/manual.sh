#!/bin/bash
# =============================================================================
# Manual Steps for Cochlearis Dev Environment
# =============================================================================
#
# This script documents manual steps required for the deployment that cannot
# be fully automated via Terraform. Run these commands as needed.
#
# Prerequisites:
#   - aws-vault configured with 'cochlearis' profile
#   - AWS CLI installed
#   - Terraform installed
#
# Usage:
#   # Source this file to get helper functions
#   source manual.sh
#
#   # Or run individual sections:
#   ./manual.sh ses_verify
#   ./manual.sh zitadel_credentials
#   ./manual.sh bookstack_oidc
# =============================================================================

set -e

REGION="eu-central-1"
DOMAIN="almondbread.org"
AWS_CMD="aws-vault exec cochlearis --no-session -- aws"

# =============================================================================
# SES Domain Verification
# =============================================================================
# Required for: Zitadel email verification, Zulip email notifications
#
# After running this, you must add DNS records to your domain.

ses_verify() {
    echo "=== SES Domain Verification ==="
    echo ""
    echo "Verifying domain: $DOMAIN"

    VERIFICATION_TOKEN=$($AWS_CMD ses verify-domain-identity \
        --domain "$DOMAIN" \
        --region "$REGION" \
        --query 'VerificationToken' \
        --output text)

    echo ""
    echo "Add this TXT record to your DNS:"
    echo "  Name:  _amazonses.$DOMAIN"
    echo "  Type:  TXT"
    echo "  Value: $VERIFICATION_TOKEN"
    echo ""

    # Also get DKIM tokens for better deliverability
    echo "Generating DKIM tokens..."
    DKIM_TOKENS=$($AWS_CMD ses verify-domain-dkim \
        --domain "$DOMAIN" \
        --region "$REGION" \
        --query 'DkimTokens' \
        --output text)

    echo ""
    echo "Add these CNAME records for DKIM:"
    for token in $DKIM_TOKENS; do
        echo "  Name:  ${token}._domainkey.$DOMAIN"
        echo "  Type:  CNAME"
        echo "  Value: ${token}.dkim.amazonses.com"
        echo ""
    done

    echo "After adding DNS records, check verification status with:"
    echo "  $AWS_CMD ses get-identity-verification-attributes --identities $DOMAIN --region $REGION"
}

ses_check_status() {
    echo "=== SES Domain Verification Status ==="
    $AWS_CMD ses get-identity-verification-attributes \
        --identities "$DOMAIN" \
        --region "$REGION"
}

ses_request_production() {
    echo "=== Request SES Production Access ==="
    echo ""
    echo "SES is in sandbox mode by default. To send emails to unverified addresses,"
    echo "you must request production access via the AWS Console:"
    echo ""
    echo "1. Go to: https://$REGION.console.aws.amazon.com/ses/home?region=$REGION#/account"
    echo "2. Click 'Request production access'"
    echo "3. Fill out the form with your use case"
    echo ""
    echo "Until approved, you can only send to verified email addresses."
}

# =============================================================================
# Zitadel Credentials
# =============================================================================
# Get admin credentials for Zitadel login

zitadel_credentials() {
    echo "=== Zitadel Admin Credentials ==="
    echo ""
    echo "URL: https://auth.dev.$DOMAIN"
    echo ""
    echo "Username: admin@zitadel.auth.dev.$DOMAIN"
    echo -n "Password: "

    $AWS_CMD secretsmanager get-secret-value \
        --secret-id cochlearis-dev-zitadel-master-key \
        --region "$REGION" \
        --query 'SecretString' \
        --output text | jq -r '.admin_password'
}

# =============================================================================
# BookStack OIDC Configuration
# =============================================================================
# After Zitadel is running, create an OIDC client for BookStack

bookstack_oidc() {
    echo "=== BookStack OIDC Configuration ==="
    echo ""
    echo "1. Login to Zitadel at https://auth.dev.$DOMAIN"
    echo "   (use 'zitadel_credentials' to get the admin password)"
    echo ""
    echo "2. Create a new project (if not exists):"
    echo "   - Go to Projects > Create New Project"
    echo "   - Name: 'Cochlearis'"
    echo ""
    echo "3. Create an OIDC application:"
    echo "   - Go to Projects > Cochlearis > Applications > Create New Application"
    echo "   - Name: 'BookStack'"
    echo "   - Type: Web"
    echo "   - Authentication Method: Code (PKCE)"
    echo "   - Redirect URIs: https://docs.dev.$DOMAIN/oidc/callback"
    echo "   - Post Logout URIs: https://docs.dev.$DOMAIN/"
    echo ""
    echo "4. Copy the Client ID and Client Secret"
    echo ""
    echo "5. Update BookStack configuration in Terraform:"
    echo "   - Edit environments/aws/dev/main.tf"
    echo "   - Set oidc_client_id and oidc_client_secret in the bookstack module"
    echo "   - Run terraform apply"
    echo ""
    echo "Alternatively, create a secret in AWS Secrets Manager:"
    echo "  $AWS_CMD secretsmanager create-secret \\"
    echo "    --name cochlearis-dev-bookstack-oidc \\"
    echo "    --secret-string '{\"client_id\":\"YOUR_CLIENT_ID\",\"client_secret\":\"YOUR_SECRET\"}' \\"
    echo "    --region $REGION"
}

# =============================================================================
# Zulip OIDC Configuration (Optional)
# =============================================================================
# If you want to use Zitadel for Zulip authentication

zulip_oidc() {
    echo "=== Zulip OIDC Configuration ==="
    echo ""
    echo "1. Login to Zitadel at https://auth.dev.$DOMAIN"
    echo ""
    echo "2. Create an OIDC application:"
    echo "   - Go to Projects > Cochlearis > Applications > Create New Application"
    echo "   - Name: 'Zulip'"
    echo "   - Type: Web"
    echo "   - Authentication Method: Code"
    echo "   - Redirect URIs: https://chat.dev.$DOMAIN/complete/oidc/"
    echo "   - Post Logout URIs: https://chat.dev.$DOMAIN/"
    echo ""
    echo "3. The Zulip configuration already expects GenericOpenIdConnectBackend."
    echo "   You'll need to update the OIDC settings in Zulip's admin panel"
    echo "   or via environment variables."
}

# =============================================================================
# Local Development Setup
# =============================================================================

local_hosts() {
    echo "=== Configure /etc/hosts for Local Development ==="
    echo ""
    echo "Add these entries to /etc/hosts:"
    echo ""
    echo "127.0.0.1 auth.local.test chat.local.test docs.local.test site.local.test"
    echo ""
    echo "Or run:"
    echo "  sudo sh -c 'echo \"127.0.0.1 auth.local.test chat.local.test docs.local.test site.local.test\" >> /etc/hosts'"
}

# =============================================================================
# Health Checks
# =============================================================================

health_check() {
    echo "=== Service Health Check ==="
    echo ""

    echo "Zitadel (https://auth.dev.$DOMAIN):"
    curl -s -o /dev/null -w "  HTTP %{http_code}\n" "https://auth.dev.$DOMAIN/debug/healthz" 2>/dev/null || echo "  Not responding"

    echo ""
    echo "Zulip (https://chat.dev.$DOMAIN):"
    curl -s -o /dev/null -w "  HTTP %{http_code}\n" "https://chat.dev.$DOMAIN/health" 2>/dev/null || echo "  Not responding"

    echo ""
    echo "BookStack (https://docs.dev.$DOMAIN):"
    curl -s -o /dev/null -w "  HTTP %{http_code}\n" "https://docs.dev.$DOMAIN/status" 2>/dev/null || echo "  Not responding"

    echo ""
    echo "ECS Task Status:"
    $AWS_CMD ecs list-tasks \
        --cluster cochlearis-dev-cluster \
        --region "$REGION" \
        --query 'taskArns' \
        --output table
}

ecs_logs() {
    local service=${1:-zulip}
    echo "=== ECS Logs for $service ==="
    $AWS_CMD logs tail "/ecs/cochlearis-dev/$service" \
        --region "$REGION" \
        --follow
}

# =============================================================================
# Main
# =============================================================================

show_help() {
    echo "Usage: ./manual.sh <command>"
    echo ""
    echo "Commands:"
    echo "  ses_verify          - Verify domain in SES (generates DNS records)"
    echo "  ses_check_status    - Check SES domain verification status"
    echo "  ses_request_production - Instructions for SES production access"
    echo "  zitadel_credentials - Get Zitadel admin password"
    echo "  bookstack_oidc      - Instructions for BookStack OIDC setup"
    echo "  zulip_oidc          - Instructions for Zulip OIDC setup"
    echo "  local_hosts         - Configure /etc/hosts for local dev"
    echo "  health_check        - Check health of all services"
    echo "  ecs_logs <service>  - Tail ECS logs (default: zulip)"
    echo ""
    echo "Example:"
    echo "  ./manual.sh zitadel_credentials"
    echo "  ./manual.sh ecs_logs zitadel"
}

# Run command if provided as argument
if [[ $# -gt 0 ]]; then
    case "$1" in
        ses_verify|ses_check_status|ses_request_production|zitadel_credentials|bookstack_oidc|zulip_oidc|local_hosts|health_check)
            "$1"
            ;;
        ecs_logs)
            ecs_logs "$2"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
fi
