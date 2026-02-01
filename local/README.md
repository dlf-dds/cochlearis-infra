# Local Development Environment

This directory contains a Docker Compose setup that mirrors the ECS Fargate deployment, allowing you to test services locally before deploying to AWS.

## Prerequisites

- Docker Desktop
- Make (comes with macOS)
- curl and jq (for status checks)

## Quick Start

```bash
# Start all services (Zitadel, Mattermost, BookStack, Traefik)
docker compose up -d

# Check service health
docker compose ps
```

> **Note**: The `.localhost` TLD is special-cased by browsers to resolve to 127.0.0.1, so no `/etc/hosts` modification is needed.

## Service URLs

| Service     | Local URL                  | Default Credentials                    |
|-------------|----------------------------|----------------------------------------|
| Zitadel     | http://auth.localhost      | admin@zitadel.auth.localhost / Password1! |
| Mattermost  | http://chat.localhost      | (create account on first visit)        |
| BookStack   | http://docs.localhost      | (uses Zitadel OIDC)                    |
| Traefik     | http://localhost:8080      | (dashboard, no auth)                   |

## Available Commands

```bash
make help       # Show all available commands
make up         # Start all services
make down       # Stop all services
make status     # Check health of all services
make logs       # Follow logs for all services
make clean      # Stop and remove all data (fresh start)
```

### Individual Services

```bash
make zitadel     # Start only Zitadel
make mattermost  # Start only Mattermost
make bookstack   # Start only BookStack
```

### View Logs

```bash
make logs-zitadel
make logs-mattermost
make logs-bookstack
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Traefik (Reverse Proxy)                  │
│                     Port 80 - Host-based routing             │
└─────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│    Zitadel      │  │   Mattermost    │  │   BookStack     │
│  auth.localhost │  │ chat.localhost  │  │ docs.localhost  │
│    :8080        │  │    :8065        │  │     :80         │
└─────────────────┘  └─────────────────┘  └─────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│   PostgreSQL    │  │   PostgreSQL    │  │     MySQL       │
│   (zitadel-db)  │  │ (mattermost-db) │  │  (bookstack-db) │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

## Comparison with ECS Deployment

| Component          | Local                    | ECS Fargate              |
|--------------------|--------------------------|--------------------------|
| Load Balancer      | Traefik                  | AWS ALB                  |
| SSL/TLS            | None (HTTP only)         | ACM Certificates         |
| Zitadel DB         | Local PostgreSQL         | RDS PostgreSQL           |
| Mattermost DB      | Local PostgreSQL         | RDS PostgreSQL           |
| BookStack DB       | Local MySQL              | RDS MySQL                |
| Storage            | Docker Volumes           | EFS                      |
| DNS                | `.localhost` TLD         | Route53                  |

## Troubleshooting

### Services not accessible
1. Check container status: `docker compose ps`
2. View logs: `docker compose logs <service-name>`

### Zitadel taking long to start
Zitadel needs to initialize its database on first run. This can take 1-2 minutes. Check logs with:
```bash
docker compose logs zitadel
```

### Fresh start
To completely reset all data:
```bash
docker compose down -v
docker compose up -d
```

## Gotchas

### Zitadel Login V2 (404 Not Found)

Zitadel v4+ has Login V2 enabled by default, but Login V2 is a **separate application** that must be deployed alongside the Zitadel backend. Without it, accessing `/ui/v2/login/*` returns a 404 error with `{"code":5,"message":"Not Found"}`.

**Solution**: Disable Login V2 to use the classic Login V1 bundled with Zitadel:
```yaml
environment:
  - ZITADEL_DEFAULTINSTANCE_FEATURES_LOGINV2_REQUIRED=false
```

**Important**: This setting is stored in the database during initial setup. If you've already started Zitadel, you must reset the database:
```bash
docker compose down
docker volume rm local_zitadel-db-data
docker compose up -d
```

### Zitadel Admin Login Email

The admin user email is **not** just `admin`. Zitadel creates it as:
```
admin@zitadel.<external-domain>
```

For our setup with `ZITADEL_EXTERNALDOMAIN=auth.localhost`, the admin email is:
```
admin@zitadel.auth.localhost
```

Password: `Password1!`

### Zulip on ARM Macs (Apple Silicon)

Zulip only provides x86 Docker images (`zulip/docker-zulip:latest` is amd64-only). On ARM Macs, x86 emulation via Rosetta causes the database connection check to timeout repeatedly during initialization - the emulated Python is too slow to complete the check within the hardcoded 60-second timeout.

**Solution**: Zulip is placed behind a Docker Compose profile and won't start by default:
```bash
# Start without Zulip (default - works on all Macs)
docker compose up -d

# Start with Zulip (x86 machines only, or wait for ARM64 images)
docker compose --profile zulip up -d
```

**For AWS ECS**: Zulip works fine on ECS Fargate x86 instances. The ARM limitation only affects local development on Apple Silicon.

### BookStack OIDC with Zitadel

BookStack is configured to use Zitadel for OIDC authentication. Before it works, you need to create an OIDC client in Zitadel:

1. Go to http://auth.localhost/ui/console
2. Login as `admin@zitadel.auth.localhost` / `Password1!`
3. Create a new project and add a Web application with:
   - Client ID: `bookstack-local`
   - Redirect URI: `http://docs.localhost/oidc/callback`

## Notes

- This setup is for **local development and testing only**
- Passwords are hardcoded for convenience (never use in production)
- Data is stored in Docker volumes and persists between restarts
- The `.localhost` TLD is special-cased by browsers to resolve to 127.0.0.1
