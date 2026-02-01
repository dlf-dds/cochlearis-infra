# Local Development Environment for Cochlearis Services
# ======================================================

.PHONY: help up down logs status clean zitadel mattermost zulip bookstack ps simple simple-up simple-down simple-logs simple-status simple-clean

# Default target
help:
	@echo "Cochlearis Local Development Environment"
	@echo "========================================="
	@echo ""
	@echo "QUICK START:"
	@echo "  make up       - Start all services (Zitadel, Mattermost, BookStack, Traefik)"
	@echo "  make status   - Check health of all services"
	@echo "  make down     - Stop all services"
	@echo "  make clean    - Remove all containers and volumes"
	@echo ""
	@echo "  URLs:"
	@echo "    http://auth.localhost      - Zitadel"
	@echo "    http://chat.localhost      - Mattermost"
	@echo "    http://docs.localhost      - BookStack (OIDC via Zitadel)"
	@echo "    http://localhost:8080      - Traefik Dashboard"
	@echo ""
	@echo "  Zitadel Login:"
	@echo "    Email:    admin@zitadel.auth.localhost"
	@echo "    Password: Password1!"
	@echo ""
	@echo "Individual Services:"
	@echo "  zitadel       - Start only Zitadel and its database"
	@echo "  mattermost    - Start only Mattermost and its database"
	@echo "  bookstack     - Start only BookStack and its database"

# Start all services
up:
	@echo "Starting all services (Zitadel, Mattermost, BookStack, Traefik)..."
	@echo "This may take a few minutes on first run."
	docker compose up -d
	@echo ""
	@echo "Services starting. Run 'make status' to check health."
	@echo ""
	@echo "URLs:"
	@echo "  http://auth.localhost      - Zitadel"
	@echo "  http://chat.localhost      - Mattermost"
	@echo "  http://docs.localhost      - BookStack"
	@echo "  http://localhost:8080      - Traefik Dashboard"
	@echo ""
	@echo "Zitadel Login:"
	@echo "  Email:    admin@zitadel.auth.localhost"
	@echo "  Password: Password1!"

# Stop all services
down:
	docker compose down

# Show running containers
ps:
	docker compose ps

# Follow logs
logs:
	docker compose logs -f

logs-zitadel:
	docker compose logs -f zitadel zitadel-db

logs-mattermost:
	docker compose logs -f mattermost mattermost-db

logs-bookstack:
	docker compose logs -f bookstack bookstack-db

# Check health status
status:
	@echo "Service Health Status"
	@echo "====================="
	@echo ""
	@echo "Traefik:"
	@curl -s http://localhost:8080/api/overview 2>/dev/null | jq -r '.http.routers.total // "not running"' || echo "  Not running"
	@echo ""
	@echo "Zitadel:"
	@curl -s -o /dev/null -w "  HTTP %{http_code}" http://auth.localhost/debug/healthz 2>/dev/null || echo "  Not ready"
	@echo ""
	@echo "Mattermost:"
	@curl -s -o /dev/null -w "  HTTP %{http_code}" http://chat.localhost/api/v4/system/ping 2>/dev/null || echo "  Not ready"
	@echo ""
	@echo "BookStack:"
	@curl -s -o /dev/null -w "  HTTP %{http_code}" http://docs.localhost/status 2>/dev/null || echo "  Not ready"
	@echo ""
	@echo ""
	@echo "Container Status:"
	@docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}"

# Start individual services
zitadel:
	docker compose up -d traefik zitadel-db zitadel
	@echo "Zitadel starting at http://auth.localhost"
	@echo "Login: admin@zitadel.auth.localhost / Password1!"

mattermost:
	docker compose up -d traefik mattermost-db mattermost
	@echo "Mattermost starting at http://chat.localhost"

bookstack:
	docker compose up -d traefik bookstack-db bookstack
	@echo "BookStack starting at http://docs.localhost"

# Clean up everything
clean:
	@echo "Stopping and removing all containers, volumes, and networks..."
	docker compose down -v --remove-orphans
	@echo "Done!"

# Rebuild containers (useful after config changes)
rebuild:
	docker compose build --no-cache
	docker compose up -d --force-recreate

# Show container resource usage
stats:
	docker compose stats

# Wait for services to be healthy
wait:
	@echo "Waiting for services to be healthy..."
	@timeout=300; \
	while [ $$timeout -gt 0 ]; do \
		if curl -s http://auth.localhost/debug/healthz >/dev/null 2>&1; then \
			echo "Zitadel: healthy"; \
			break; \
		fi; \
		echo "Waiting for Zitadel... ($$timeout s remaining)"; \
		sleep 5; \
		timeout=$$((timeout - 5)); \
	done

# =============================================================================
# SIMPLIFIED MODE (no Traefik, direct port exposure)
# =============================================================================

simple-up:
	@echo "Starting services in simplified mode (no Traefik)..."
	docker compose -f docker-compose.simple.yml up -d
	@echo ""
	@echo "Services starting. Run 'make simple-status' to check health."
	@echo ""
	@echo "URLs:"
	@echo "  http://localhost:8080  - Zitadel (admin / Password1!)"
	@echo "  http://localhost:8081  - Zulip"
	@echo "  http://localhost:8082  - BookStack (admin@admin.com / password)"

simple-down:
	docker compose -f docker-compose.simple.yml down

simple-ps:
	docker compose -f docker-compose.simple.yml ps

simple-logs:
	docker compose -f docker-compose.simple.yml logs -f

simple-status:
	@echo "Service Health Status (Simplified Mode)"
	@echo "========================================"
	@echo ""
	@echo "Zitadel (localhost:8080):"
	@curl -s -o /dev/null -w "  HTTP %{http_code}\n" http://localhost:8080/debug/healthz 2>/dev/null || echo "  Not ready"
	@echo ""
	@echo "Zulip (localhost:8081):"
	@curl -s -o /dev/null -w "  HTTP %{http_code}\n" http://localhost:8081/health 2>/dev/null || echo "  Not ready"
	@echo ""
	@echo "BookStack (localhost:8082):"
	@curl -s -o /dev/null -w "  HTTP %{http_code}\n" http://localhost:8082/status 2>/dev/null || echo "  Not ready"
	@echo ""
	@echo "Container Status:"
	@docker compose -f docker-compose.simple.yml ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}"

simple-clean:
	@echo "Stopping and removing all containers, volumes, and networks (simplified mode)..."
	docker compose -f docker-compose.simple.yml down -v --remove-orphans
	@echo "Done!"

simple-wait:
	@echo "Waiting for services to be healthy..."
	@timeout=300; \
	while [ $$timeout -gt 0 ]; do \
		if curl -s http://localhost:8080/debug/healthz >/dev/null 2>&1; then \
			echo "Zitadel: healthy"; \
			break; \
		fi; \
		echo "Waiting for Zitadel... ($$timeout s remaining)"; \
		sleep 5; \
		timeout=$$((timeout - 5)); \
	done
