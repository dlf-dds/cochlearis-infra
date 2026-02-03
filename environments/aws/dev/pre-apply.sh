#!/bin/bash
# Pre-apply check: Remove orphaned zitadel_oidc resources from state
# These resources require the zitadel provider which is in dev/oidc/, not here.
#
# Run before terraform apply to avoid "Missing required argument" errors.

set -e

echo "Checking for orphaned zitadel_oidc resources in state..."

# Get list of resources that require the zitadel provider
ORPHANED=$(terraform state list 2>/dev/null | grep -E '^(module\.zitadel_oidc|data\.aws_ssm_parameter\.zitadel_org_id|data\.aws_secretsmanager_secret_version\.zitadel_service_account)' || true)

if [ -z "$ORPHANED" ]; then
    echo "No orphaned zitadel resources found. Safe to apply."
    exit 0
fi

echo "Found orphaned resources that require zitadel provider:"
echo "$ORPHANED"
echo ""
echo "Removing from state (resources will be managed by dev/oidc/ instead)..."

for resource in $ORPHANED; do
    echo "  Removing: $resource"
    terraform state rm "$resource" || true
done

echo ""
echo "Done. You can now run terraform apply."
