# RailDock Dev Makefile
# Local dev uses docker-compose.dev.yml to mount live code
# Production uses docker-compose.yml (pre-built image)

B := \033[0;34m
G := \033[0;32m
Y := \033[1;33m
R := \033[0;31m
N := \033[0m

COMPOSE_DEV := docker compose -f docker-compose.yml -f docker-compose.dev.yml
COMPOSE_PROD := docker compose -f docker-compose.yml

.PHONY: help install uninstall start stop restart status logs ps db console test seed setup-dev reset-db fix-hmr build build-prod push tag

help:
	@printf "\n$(B)RailDock Commands$(N)\n\n"
	@printf "  $(G)make start$(N)          Start dev stack (live code reloading)\n"
	@printf "  $(G)make stop$(N)           Stop all containers\n"
	@printf "  $(G)make restart$(N)        Stop and start everything\n"
	@printf "  $(G)make status$(N)         Show container status\n"
	@printf "  $(G)make logs$(N)           Tail all logs\n"
	@printf "  $(G)make logs-db$(N)        Tail DB logs\n"
	@printf "  $(G)make ps$(N)             Show running containers\n"
	@printf "  $(G)make db$(N)             Open PostgreSQL console\n"
	@printf "  $(G)make console$(N)        Open Rails console\n"
	@printf "  $(G)make test$(N)           Run frontend Vitest tests\n"
	@printf "  $(G)make seed$(N)           Run Rails db:seed\n"
	@printf "  $(G)make setup-dev$(N)      One-click dev setup (env, keys, server, migrations)\n"
	@printf "  $(G)make reset-db$(N)        Wipe and recreate dev database\n"
	@printf "  $(G)make fix-hmr$(N)        Restart frontend (fixes stale Vite cache)\n"
	@printf "  $(G)make install$(N)        Run install.sh (production install)\n"
	@printf "  $(G)make uninstall$(N)      Uninstall RailDock\n"
	@printf "  $(G)make build-prod$(N)     Build production Docker image locally\n"
	@printf "  $(G)make push$(N)           Push image to GHCR (run build first)\n"
	@printf "\n  URL: http://localhost:3000 (backend) + http://localhost:5173 (Vite dev)\n\n"

status:
	@printf "$(B)=== Containers ===$(N)\n"
	@$(COMPOSE_DEV) ps

start:
	@printf "$(B)[make]$(N) Starting RailDock dev stack...\n"
	@$(COMPOSE_DEV) up -d --build
	@printf "$(B)[make]$(N) Waiting for backend health...\n"
	@for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do \
		if curl -sf http://localhost:3000/api/health >/dev/null 2>&1; then \
			printf "$(G)[make]$(N) Backend is healthy at :3000\n"; \
			break; \
		fi; \
		sleep 2; \
		if [ $$i -eq 15 ]; then \
			printf "$(Y)[make]$(N) Backend not healthy yet — check: make logs\n"; \
		fi; \
	done
	@printf "$(G)[make]$(N) Dev stack is up\n"
	@printf "$(B)[make]$(N) Backend:  http://localhost:3000\n"
	@printf "$(B)[make]$(N) Vite:     http://localhost:5173\n"

stop:
	@printf "$(B)[make]$(N) Stopping containers...\n"
	@-$(COMPOSE_DEV) down >/dev/null 2>&1 || true
	@printf "$(G)[make]$(N) Stopped\n"

restart: stop start

logs:
	@$(COMPOSE_DEV) logs -f

logs-db:
	@$(COMPOSE_DEV) logs -f db

ps:
	@$(COMPOSE_DEV) ps

db:
	@docker exec -it raildock-db-1 psql -U raildock -d raildock_development

console:
	@docker exec -it raildock-raildock-1 bin/rails console

test:
	@cd app && npm test

seed:
	@printf "$(B)[make]$(N) Running db:seed...\n"
	@docker exec raildock-raildock-1 sh -c 'cd /rails && bin/rails db:seed'
	@printf "$(G)[make]$(N) Done\n"

setup-dev:
	@bash scripts/setup-dev.sh

install:
	@bash install.sh

uninstall:
	@bash uninstall.sh

reset-db:
	@printf "$(Y)[make]$(N) WARNING: This destroys all data in the dev database\n"
	@read -p "Are you sure? [y/N] " confirm && [ "$${confirm}" = "y" ] || exit 0
	@docker exec raildock-raildock-1 sh -c 'cd /rails && DISABLE_DATABASE_ENVIRONMENT_CHECK=1 bin/rails db:drop db:create db:migrate'
	@printf "$(G)[make]$(N) Database reset\n"

fix-hmr:
	@printf "$(B)[make]$(N) Restarting frontend container to pick up latest source...\n"
	@docker restart raildock-frontend-1 2>/dev/null || true
	@sleep 3
	@printf "$(G)[make]$(N) Frontend restarted.\n"
	@printf "$(Y)[make]$(N) 👉 Hard-refresh your browser: Cmd+Shift+R (Mac) or Ctrl+Shift+R (Win/Lin)\n"

build-prod:
	@printf "$(B)[make]$(N) Building production image...\n"
	@docker buildx build --platform linux/amd64,linux/arm64 \
		--tag ghcr.io/mona-chen/raildock/raildock:latest \
		--load .
	@printf "$(G)[make]$(N) Image built: ghcr.io/mona-chen/raildock/raildock:latest\n"

push:
	@printf "$(B)[make]$(N) Pushing image to GHCR...\n"
	@docker push ghcr.io/mona-chen/raildock/raildock:latest
	@printf "$(G)[make]$(N) Image pushed\n"

tag:
	@git tag "v$$(date +%Y%m%d-%H%M%S)" && git push --tags
	@printf "$(G)[make]$(N) Tagged and pushed\n"
