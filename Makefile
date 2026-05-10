# RailDock Dev Makefile
# Run these directly on your Mac (uses Colima for lightweight Docker)

B := \033[0;34m
G := \033[0;32m
Y := \033[1;33m
R := \033[0;31m
N := \033[0m

COMPOSE := docker compose -f docker-compose.yml -f docker-compose.dev.yml

.PHONY: help install start stop restart status logs ps db console test seed setup-dev reset-db fix-hmr restart-backend

help:
	@printf "\n$(B)RailDock Dev Commands$(N)\n\n"
	@printf "  $(G)make start$(N)          Start the full dev stack\n"
	@printf "  $(G)make setup-dev$(N)      One-click dev setup (env, keys, server, migrations)\n"
	@printf "  $(G)make stop$(N)           Stop all containers\n"
	@printf "  $(G)make restart$(N)        Stop and start everything\n"
	@printf "  $(G)make status$(N)         Show container status\n"
	@printf "  $(G)make logs$(N)           Tail all logs\n"
	@printf "  $(G)make logs-backend$(N)   Tail backend logs\n"
	@printf "  $(G)make logs-frontend$(N)  Tail frontend logs\n"
	@printf "  $(G)make ps$(N)             Show running containers\n"
	@printf "  $(G)make db$(N)             Open PostgreSQL console\n"
	@printf "  $(G)make console$(N)        Open Rails console\n"
	@printf "  $(G)make test$(N)           Run frontend Vitest tests\n"
	@printf "  $(G)make seed$(N)           Run Rails db:seed (sample data)\n"
	@printf "  $(G)make reset-db$(N)       Wipe and recreate dev database\n"
	@printf "  $(G)make fix-hmr$(N)        Restart frontend (fixes stale Vite cache)\n"
	@printf "  $(G)make restart-backend$(N) Copy backend code and restart container\n"
	@printf "\n  URL: http://localhost:8090\n\n"

status:
	@printf "$(B)=== Containers ===$(N)\n"
	@$(COMPOSE) ps

start:
	@printf "$(B)[make]$(N) Starting RailDock dev stack...\n"
	@$(COMPOSE) up -d --build
	@printf "$(B)[make]$(N) Waiting for backend health...\n"
	@for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do \
		if docker exec raildock-backend-1 curl -sf http://localhost:3000/api/health >/dev/null 2>&1; then \
			printf "$(G)[make]$(N) Backend is healthy\n"; \
			break; \
		fi; \
		sleep 2; \
		if [ $$i -eq 15 ]; then \
			printf "$(Y)[make]$(N) Backend not healthy yet — check: make logs-backend\n"; \
		fi; \
	done
	@printf "$(G)[make]$(N) RailDock is up at http://localhost:8090\n"
	@printf "$(B)[make]$(N) Run $(Y)make setup-dev$(N) to auto-configure the local Dokku server, or use the web UI to set up manually.\n"

stop:
	@printf "$(B)[make]$(N) Stopping containers...\n"
	@-$(COMPOSE) down >/dev/null 2>&1 || true
	@printf "$(G)[make]$(N) Stopped\n"

restart: stop start

logs:
	@$(COMPOSE) logs -f

logs-backend:
	@$(COMPOSE) logs -f backend

logs-frontend:
	@$(COMPOSE) logs -f frontend

logs-db:
	@$(COMPOSE) logs -f db

ps:
	@$(COMPOSE) ps

db:
	@docker exec -it raildock-db-1 psql -U raildock -d raildock_production

console:
	@docker exec -it raildock-backend-1 bin/rails console

test:
	@cd app && npm test

seed:
	@printf "$(B)[make]$(N) Running db:seed...\n"
	@docker exec raildock-backend-1 sh -c 'cd /rails && bin/rails db:seed'
	@printf "$(G)[make]$(N) Done\n"

setup-dev:
	@bash scripts/setup-dev.sh

install:
	@bash install.sh

reset-db:
	@printf "$(Y)[make]$(N) WARNING: This destroys all data in the dev database\n"
	@read -p "Are you sure? [y/N] " confirm && [ "$${confirm}" = "y" ] || exit 0
	@docker exec raildock-backend-1 sh -c 'cd /rails && DISABLE_DATABASE_ENVIRONMENT_CHECK=1 bin/rails db:drop db:create db:migrate'
	@printf "$(G)[make]$(N) Database reset\n"
	@printf "$(B)[make]$(N) Run $(Y)make setup-dev$(N) to auto-configure the local Dokku server, or use the web UI to set up manually.\n"

fix-hmr:
	@printf "$(B)[make]$(N) Restarting frontend container to pick up latest source...\n"
	@docker restart raildock-frontend-1
	@sleep 3
	@printf "$(G)[make]$(N) Frontend restarted.\n"
	@printf "$(Y)[make]$(N) 👉 Hard-refresh your browser: Cmd+Shift+R (Mac) or Ctrl+Shift+R (Win/Lin)\n"

restart-backend:
	@printf "$(B)[make]$(N) Copying backend code and restarting backend + worker...\n"
	@docker cp backend/. raildock-backend-1:/rails/ && docker cp backend/. raildock-worker-1:/rails/
	@docker restart raildock-backend-1 raildock-worker-1
	@printf "$(B)[make]$(N) Waiting for backend health...\n"
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
		if docker exec raildock-backend-1 curl -sf http://localhost:3000/api/health >/dev/null 2>&1; then \
			printf "$(G)[make]$(N) Backend is healthy\n"; \
			break; \
		fi; \
		sleep 2; \
		if [ $$i -eq 10 ]; then \
			printf "$(Y)[make]$(N) Backend not healthy yet — check: make logs-backend\n"; \
		fi; \
	done
