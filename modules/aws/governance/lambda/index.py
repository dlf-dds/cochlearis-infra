"""
Lifecycle Manager Lambda Function

Performs weekly governance checks:
1. Scans resources for lifecycle tags (ExpiresAt, CreatedAt)
2. Sends warnings for resources approaching expiration
3. Optionally terminates expired resources
4. Generates cost reports by project/owner
"""

import os
import json
import boto3
from datetime import datetime, timedelta
from collections import defaultdict

# Environment variables
PROJECT = os.environ.get('PROJECT', 'unknown')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'unknown')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')
OWNER_EMAIL = os.environ.get('OWNER_EMAIL')
WARNING_DAYS = int(os.environ.get('WARNING_DAYS', '30'))
TERMINATION_DAYS = int(os.environ.get('TERMINATION_DAYS', '60'))
ENABLE_AUTO_TERMINATION = os.environ.get('ENABLE_AUTO_TERMINATION', 'false').lower() == 'true'
MONTHLY_BUDGET = float(os.environ.get('MONTHLY_BUDGET', '200'))


def handler(event, context):
    """Main Lambda handler."""
    print(f"Starting governance check for {PROJECT}-{ENVIRONMENT}")

    results = {
        'resources_checked': 0,
        'warnings_sent': 0,
        'resources_terminated': 0,
        'cost_report': None,
        'errors': []
    }

    try:
        # Check resource lifecycle
        lifecycle_results = check_resource_lifecycle()
        results['resources_checked'] = lifecycle_results['checked']
        results['warnings_sent'] = lifecycle_results['warnings']
        results['resources_terminated'] = lifecycle_results['terminated']

        # Generate cost report
        cost_report = generate_cost_report()
        results['cost_report'] = cost_report

        # Send weekly summary
        send_weekly_summary(results, lifecycle_results, cost_report)

    except Exception as e:
        results['errors'].append(str(e))
        print(f"Error during governance check: {e}")
        send_error_notification(str(e))

    return results


def check_resource_lifecycle():
    """Check all tagged resources for lifecycle compliance."""
    tagging = boto3.client('resourcegroupstaggingapi')

    results = {
        'checked': 0,
        'warnings': 0,
        'terminated': 0,
        'expiring_soon': [],
        'expired': []
    }

    # Get all resources tagged with our project
    paginator = tagging.get_paginator('get_resources')

    for page in paginator.paginate(
        TagFilters=[{'Key': 'Project', 'Values': [PROJECT]}]
    ):
        for resource in page.get('ResourceTagMappingList', []):
            results['checked'] += 1
            arn = resource['ResourceARN']
            tags = {t['Key']: t['Value'] for t in resource.get('Tags', [])}

            # Check lifecycle tags
            created_at = tags.get('CreatedAt')
            expires_at = tags.get('ExpiresAt')
            lifecycle = tags.get('Lifecycle', 'persistent')

            if lifecycle == 'persistent':
                continue  # Skip persistent resources

            if expires_at:
                expiry_date = datetime.fromisoformat(expires_at.replace('Z', '+00:00'))
                now = datetime.now(expiry_date.tzinfo)
                days_until_expiry = (expiry_date - now).days

                if days_until_expiry < 0:
                    # Resource has expired
                    results['expired'].append({
                        'arn': arn,
                        'expires_at': expires_at,
                        'days_expired': abs(days_until_expiry),
                        'owner': tags.get('Owner', OWNER_EMAIL)
                    })
                elif days_until_expiry <= WARNING_DAYS:
                    # Resource expiring soon
                    results['expiring_soon'].append({
                        'arn': arn,
                        'expires_at': expires_at,
                        'days_remaining': days_until_expiry,
                        'owner': tags.get('Owner', OWNER_EMAIL)
                    })
            elif created_at and lifecycle == 'temporary':
                # No explicit expiry, calculate from creation date
                created_date = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
                now = datetime.now(created_date.tzinfo)
                days_since_creation = (now - created_date).days

                if days_since_creation >= TERMINATION_DAYS:
                    results['expired'].append({
                        'arn': arn,
                        'created_at': created_at,
                        'days_old': days_since_creation,
                        'owner': tags.get('Owner', OWNER_EMAIL)
                    })
                elif days_since_creation >= WARNING_DAYS:
                    results['expiring_soon'].append({
                        'arn': arn,
                        'created_at': created_at,
                        'days_old': days_since_creation,
                        'days_remaining': TERMINATION_DAYS - days_since_creation,
                        'owner': tags.get('Owner', OWNER_EMAIL)
                    })

    # Send warnings for expiring resources
    if results['expiring_soon']:
        send_expiration_warnings(results['expiring_soon'])
        results['warnings'] = len(results['expiring_soon'])

    # Handle expired resources
    if results['expired']:
        if ENABLE_AUTO_TERMINATION:
            for resource in results['expired']:
                try:
                    terminate_resource(resource['arn'])
                    results['terminated'] += 1
                except Exception as e:
                    print(f"Failed to terminate {resource['arn']}: {e}")
        else:
            send_expiration_alerts(results['expired'])

    return results


def generate_cost_report():
    """Generate cost report using Cost Explorer."""
    ce = boto3.client('ce')

    # Get date range (last 30 days)
    end_date = datetime.now().strftime('%Y-%m-%d')
    start_date = (datetime.now() - timedelta(days=30)).strftime('%Y-%m-%d')

    report = {
        'period': {'start': start_date, 'end': end_date},
        'total_cost': 0,
        'by_service': {},
        'by_tag': {},
        'forecast': None,
        'budget_status': None
    }

    try:
        # Get costs by service
        response = ce.get_cost_and_usage(
            TimePeriod={'Start': start_date, 'End': end_date},
            Granularity='MONTHLY',
            Metrics=['UnblendedCost'],
            GroupBy=[{'Type': 'DIMENSION', 'Key': 'SERVICE'}],
            Filter={
                'Tags': {
                    'Key': 'Project',
                    'Values': [PROJECT]
                }
            }
        )

        for result in response.get('ResultsByTime', []):
            for group in result.get('Groups', []):
                service = group['Keys'][0]
                cost = float(group['Metrics']['UnblendedCost']['Amount'])
                report['by_service'][service] = report['by_service'].get(service, 0) + cost
                report['total_cost'] += cost

        # Get cost forecast
        try:
            forecast_end = (datetime.now() + timedelta(days=30)).strftime('%Y-%m-%d')
            forecast_response = ce.get_cost_forecast(
                TimePeriod={'Start': end_date, 'End': forecast_end},
                Metric='UNBLENDED_COST',
                Granularity='MONTHLY',
                Filter={
                    'Tags': {
                        'Key': 'Project',
                        'Values': [PROJECT]
                    }
                }
            )
            report['forecast'] = float(forecast_response['Total']['Amount'])
        except Exception as e:
            print(f"Could not get cost forecast: {e}")

        # Calculate budget status
        report['budget_status'] = {
            'monthly_budget': MONTHLY_BUDGET,
            'current_spend': report['total_cost'],
            'percentage_used': (report['total_cost'] / MONTHLY_BUDGET * 100) if MONTHLY_BUDGET > 0 else 0,
            'forecast': report['forecast']
        }

    except Exception as e:
        print(f"Error generating cost report: {e}")
        report['error'] = str(e)

    return report


def send_weekly_summary(results, lifecycle_results, cost_report):
    """Send weekly governance summary via SNS."""
    sns = boto3.client('sns')

    subject = f"[{PROJECT}] Weekly Governance Report - {datetime.now().strftime('%Y-%m-%d')}"

    message_parts = [
        f"Weekly Governance Report for {PROJECT}-{ENVIRONMENT}",
        f"Generated: {datetime.now().isoformat()}",
        "",
        "=" * 50,
        "RESOURCE LIFECYCLE",
        "=" * 50,
        f"Resources checked: {results['resources_checked']}",
        f"Warnings sent: {results['warnings_sent']}",
        f"Resources terminated: {results['resources_terminated']}",
    ]

    if lifecycle_results['expiring_soon']:
        message_parts.extend([
            "",
            "Resources expiring soon:",
        ])
        for r in lifecycle_results['expiring_soon'][:10]:  # Limit to 10
            message_parts.append(f"  - {r['arn']} (expires in {r.get('days_remaining', 'N/A')} days)")

    if lifecycle_results['expired']:
        message_parts.extend([
            "",
            "Expired resources:",
        ])
        for r in lifecycle_results['expired'][:10]:
            action = "TERMINATED" if ENABLE_AUTO_TERMINATION else "NEEDS ATTENTION"
            message_parts.append(f"  - {r['arn']} [{action}]")

    if cost_report and not cost_report.get('error'):
        message_parts.extend([
            "",
            "=" * 50,
            "COST REPORT (Last 30 Days)",
            "=" * 50,
            f"Total spend: ${cost_report['total_cost']:.2f}",
            f"Monthly budget: ${MONTHLY_BUDGET:.2f}",
            f"Budget used: {cost_report['budget_status']['percentage_used']:.1f}%",
        ])

        if cost_report['forecast']:
            message_parts.append(f"Forecasted monthly spend: ${cost_report['forecast']:.2f}")

        if cost_report['by_service']:
            message_parts.extend([
                "",
                "Cost by service:",
            ])
            sorted_services = sorted(cost_report['by_service'].items(), key=lambda x: x[1], reverse=True)
            for service, cost in sorted_services[:10]:
                message_parts.append(f"  - {service}: ${cost:.2f}")

    message_parts.extend([
        "",
        "=" * 50,
        "",
        f"Auto-termination: {'ENABLED' if ENABLE_AUTO_TERMINATION else 'DISABLED'}",
        f"Warning threshold: {WARNING_DAYS} days",
        f"Termination threshold: {TERMINATION_DAYS} days",
    ])

    message = "\n".join(message_parts)

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=subject,
        Message=message
    )

    print(f"Weekly summary sent to {SNS_TOPIC_ARN}")


def send_expiration_warnings(resources):
    """Send warning notifications for expiring resources."""
    sns = boto3.client('sns')

    subject = f"[{PROJECT}] Resource Expiration Warning"

    message_parts = [
        f"The following resources in {PROJECT}-{ENVIRONMENT} are approaching expiration:",
        "",
    ]

    for r in resources:
        message_parts.append(f"- {r['arn']}")
        message_parts.append(f"  Days remaining: {r.get('days_remaining', 'N/A')}")
        message_parts.append(f"  Owner: {r.get('owner', 'Unknown')}")
        message_parts.append("")

    message_parts.extend([
        "To extend these resources, update the 'ExpiresAt' tag or set 'Lifecycle' to 'persistent'.",
        "",
        f"Resources will be {'automatically terminated' if ENABLE_AUTO_TERMINATION else 'flagged for manual review'} after {TERMINATION_DAYS} days.",
    ])

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=subject,
        Message="\n".join(message_parts)
    )


def send_expiration_alerts(resources):
    """Send alerts for expired resources that need attention."""
    sns = boto3.client('sns')

    subject = f"[{PROJECT}] URGENT: Expired Resources Need Attention"

    message_parts = [
        f"The following resources in {PROJECT}-{ENVIRONMENT} have EXPIRED:",
        "",
    ]

    for r in resources:
        message_parts.append(f"- {r['arn']}")
        if 'days_expired' in r:
            message_parts.append(f"  Days expired: {r['days_expired']}")
        if 'days_old' in r:
            message_parts.append(f"  Days old: {r['days_old']}")
        message_parts.append(f"  Owner: {r.get('owner', 'Unknown')}")
        message_parts.append("")

    message_parts.extend([
        "Auto-termination is DISABLED. Please take manual action:",
        "1. Update tags to extend the resources, OR",
        "2. Manually terminate the resources if no longer needed",
    ])

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=subject,
        Message="\n".join(message_parts)
    )


def send_error_notification(error_message):
    """Send notification when an error occurs."""
    sns = boto3.client('sns')

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"[{PROJECT}] Governance Check Error",
        Message=f"An error occurred during the governance check:\n\n{error_message}"
    )


def terminate_resource(arn):
    """Terminate a resource by ARN (if auto-termination is enabled)."""
    if not ENABLE_AUTO_TERMINATION:
        print(f"Auto-termination disabled, skipping: {arn}")
        return

    # Parse ARN to determine resource type
    # arn:aws:service:region:account:resource-type/resource-id
    parts = arn.split(':')
    if len(parts) < 6:
        print(f"Invalid ARN format: {arn}")
        return

    service = parts[2]
    resource_part = parts[5]

    print(f"Attempting to terminate {service} resource: {arn}")

    if service == 'ec2':
        ec2 = boto3.client('ec2')
        if resource_part.startswith('instance/'):
            instance_id = resource_part.split('/')[1]
            ec2.terminate_instances(InstanceIds=[instance_id])
            print(f"Terminated EC2 instance: {instance_id}")

    elif service == 'rds':
        rds = boto3.client('rds')
        if resource_part.startswith('db:'):
            db_identifier = resource_part.split(':')[1]
            rds.delete_db_instance(
                DBInstanceIdentifier=db_identifier,
                SkipFinalSnapshot=True
            )
            print(f"Deleted RDS instance: {db_identifier}")

    elif service == 'ecs':
        ecs = boto3.client('ecs')
        if '/service/' in resource_part:
            # Extract cluster and service name
            parts = resource_part.split('/')
            cluster = parts[1]
            service_name = parts[2]
            ecs.update_service(
                cluster=cluster,
                service=service_name,
                desiredCount=0
            )
            ecs.delete_service(
                cluster=cluster,
                service=service_name
            )
            print(f"Deleted ECS service: {service_name}")

    elif service == 'elasticache':
        elasticache = boto3.client('elasticache')
        if resource_part.startswith('cluster:'):
            cluster_id = resource_part.split(':')[1]
            elasticache.delete_cache_cluster(CacheClusterId=cluster_id)
            print(f"Deleted ElastiCache cluster: {cluster_id}")

    else:
        print(f"Unsupported resource type for termination: {service}")
