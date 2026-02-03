"""
Mattermost <-> Outline Bi-Directional Bridge

This Lambda function serves as a multiplexer that handles:
1. OUTBOUND: Mattermost slash command → Create Outline document
2. INBOUND: Outline webhook → Notify Mattermost channel

Request routing is based on Content-Type:
- application/x-www-form-urlencoded → Mattermost slash command
- application/json → Outline webhook
"""

import json
import os
import urllib.parse
import urllib.request
import logging
import re
import boto3
from functools import lru_cache

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Secrets Manager client (reused across invocations)
secrets_client = boto3.client('secretsmanager')


@lru_cache(maxsize=4)
def get_secret(secret_arn, key):
    """Fetch and cache a secret value from Secrets Manager."""
    try:
        response = secrets_client.get_secret_value(SecretId=secret_arn)
        secret_data = json.loads(response['SecretString'])
        return secret_data.get(key, '')
    except Exception as e:
        logger.error(f"Failed to get secret {secret_arn}: {str(e)}")
        return ''


def get_outline_api_key():
    """Get Outline API key from Secrets Manager."""
    secret_arn = os.environ.get('OUTLINE_API_KEY_SECRET_ARN', '')
    if secret_arn:
        return get_secret(secret_arn, 'api_key')
    return ''


def get_mattermost_webhook_url():
    """Get Mattermost webhook URL from Secrets Manager."""
    secret_arn = os.environ.get('MATTERMOST_WEBHOOK_SECRET_ARN', '')
    if secret_arn:
        return get_secret(secret_arn, 'webhook_url')
    return ''


def handler(event, context):
    """Main Lambda handler - routes requests to appropriate handler."""
    try:
        headers = event.get('headers', {})
        # Headers may be lowercase in API Gateway HTTP API
        content_type = headers.get('content-type', headers.get('Content-Type', ''))

        logger.info(f"Received request with content-type: {content_type}")

        # OUTBOUND: Mattermost slash command (form-urlencoded)
        if 'application/x-www-form-urlencoded' in content_type:
            return handle_slash_command(event)

        # INBOUND: Outline webhook (JSON)
        if 'application/json' in content_type:
            return handle_outline_webhook(event)

        # Unknown content type
        logger.warning(f"Unknown content-type: {content_type}")
        return response(400, {"error": "Unsupported content type"})

    except Exception as e:
        logger.error(f"Handler error: {str(e)}", exc_info=True)
        return response(500, {"error": "Internal server error"})


def handle_slash_command(event):
    """
    Handle Mattermost slash command to create Outline document.

    Syntax: /outline create "Title" "Content markdown here"
    """
    try:
        body = event.get('body', '')

        # Handle base64 encoded body
        if event.get('isBase64Encoded', False):
            import base64
            body = base64.b64decode(body).decode('utf-8')

        params = dict(urllib.parse.parse_qsl(body))
        text = params.get('text', '').strip()
        user_name = params.get('user_name', 'Unknown')
        channel_name = params.get('channel_name', 'Unknown')

        logger.info(f"Slash command from {user_name} in #{channel_name}: {text[:100]}")

        # Parse command: create "Title" "Content"
        # Support both: create "Title" "Content" and create "Title"
        match = re.match(r'create\s+"([^"]+)"(?:\s+"([^"]*)")?', text)

        if not match:
            return mattermost_response(
                "Usage: `/outline create \"Document Title\" \"Document content in markdown\"`\n\n"
                "Example: `/outline create \"Meeting Notes\" \"## Attendees\\n- Alice\\n- Bob\"`"
            )

        title = match.group(1)
        content = match.group(2) or f"Created by {user_name} from Mattermost #{channel_name}"

        # Create document in Outline
        doc_url = create_outline_document(title, content, user_name, channel_name)

        if doc_url:
            return mattermost_response(
                f"**Document created:** [{title}]({doc_url})\n\n"
                f"_Created by {user_name} from #{channel_name}_"
            )
        else:
            return mattermost_response(
                "Failed to create document. Check Lambda logs for details.",
                ephemeral=True
            )

    except Exception as e:
        logger.error(f"Slash command error: {str(e)}", exc_info=True)
        return mattermost_response(f"Error: {str(e)}", ephemeral=True)


def handle_outline_webhook(event):
    """
    Handle Outline webhook to notify Mattermost.

    Outline sends webhooks for: documents.publish, documents.update, etc.
    """
    try:
        body = event.get('body', '{}')

        # Handle base64 encoded body
        if event.get('isBase64Encoded', False):
            import base64
            body = base64.b64decode(body).decode('utf-8')

        payload = json.loads(body)

        event_type = payload.get('event', '')
        model = payload.get('payload', {}).get('model', {})

        # Get document details
        doc_title = model.get('title', 'Untitled')
        doc_url_path = model.get('url', '')

        outline_base_url = os.environ.get('OUTLINE_BASE_URL', '')
        doc_url = f"{outline_base_url}{doc_url_path}" if doc_url_path else ''

        logger.info(f"Outline webhook: {event_type} - {doc_title}")

        # Build notification message based on event type
        if 'publish' in event_type:
            emoji = ":rocket:"
            action = "published"
        elif 'update' in event_type:
            emoji = ":pencil2:"
            action = "updated"
        elif 'delete' in event_type:
            emoji = ":wastebasket:"
            action = "deleted"
        elif 'archive' in event_type:
            emoji = ":file_folder:"
            action = "archived"
        else:
            # Ignore other event types
            logger.info(f"Ignoring event type: {event_type}")
            return response(200, {"status": "ignored", "event": event_type})

        # Send notification to Mattermost
        message = f"{emoji} **Document {action}:** [{doc_title}]({doc_url})"

        success = send_mattermost_notification(message)

        if success:
            return response(200, {"status": "notified", "event": event_type})
        else:
            return response(500, {"error": "Failed to send notification"})

    except Exception as e:
        logger.error(f"Webhook handler error: {str(e)}", exc_info=True)
        return response(500, {"error": str(e)})


def create_outline_document(title, content, user_name, channel_name):
    """Create a document in Outline via API."""
    try:
        outline_base_url = os.environ.get('OUTLINE_BASE_URL', '')
        outline_api_key = get_outline_api_key()
        collection_id = os.environ.get('OUTLINE_COLLECTION_ID', '')

        if not all([outline_base_url, outline_api_key, collection_id]):
            logger.error("Missing Outline configuration")
            return None

        url = f"{outline_base_url}/api/documents.create"

        # Append attribution to content
        full_content = f"{content}\n\n---\n_Created via Mattermost by {user_name} in #{channel_name}_"

        data = json.dumps({
            "title": title,
            "text": full_content,
            "collectionId": collection_id,
            "publish": True
        }).encode('utf-8')

        req = urllib.request.Request(
            url,
            data=data,
            headers={
                'Authorization': f'Bearer {outline_api_key}',
                'Content-Type': 'application/json'
            },
            method='POST'
        )

        with urllib.request.urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read().decode())
            doc_path = result.get('data', {}).get('url', '')
            if doc_path:
                return f"{outline_base_url}{doc_path}"
            return None

    except urllib.error.HTTPError as e:
        logger.error(f"Outline API error: {e.code} - {e.read().decode()}")
        return None
    except Exception as e:
        logger.error(f"Error creating document: {str(e)}", exc_info=True)
        return None


def send_mattermost_notification(message):
    """Send a notification to Mattermost via incoming webhook."""
    try:
        webhook_url = get_mattermost_webhook_url()

        if not webhook_url:
            logger.error("Missing Mattermost webhook URL")
            return False

        data = json.dumps({
            "text": message,
            "username": "Outline",
            "icon_emoji": ":book:"
        }).encode('utf-8')

        req = urllib.request.Request(
            webhook_url,
            data=data,
            headers={'Content-Type': 'application/json'},
            method='POST'
        )

        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status == 200

    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}", exc_info=True)
        return False


def mattermost_response(text, ephemeral=False):
    """Build a Mattermost slash command response."""
    body = {
        "response_type": "ephemeral" if ephemeral else "in_channel",
        "text": text
    }
    return response(200, body)


def response(status_code, body):
    """Build an API Gateway response."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": json.dumps(body)
    }
