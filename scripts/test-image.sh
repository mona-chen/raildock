#!/usr/bin/env bash
set -euo pipefail
# Fresh credentials exercise the same entrypoint used by a new installation.
image="${1:?image required}"
name="raildock-smoke-${RANDOM}"
# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() { docker rm -f "$name" "${name}-db" >/dev/null 2>&1 || true; docker network rm "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$name" >/dev/null
docker run -d --name "${name}-db" --network "$name" -e POSTGRES_USER=backend -e POSTGRES_PASSWORD=smoke postgres:16-alpine >/dev/null
for _attempt in $(seq 1 30); do
  if docker exec "${name}-db" pg_isready -U backend >/dev/null 2>&1; then break; fi
  sleep 1
done
docker run -d --name "$name" --network "$name" \
  -e RAILS_ENV=production -e SECRET_KEY_BASE="$(openssl rand -hex 64)" \
  -e JWT_SECRET_KEY="$(openssl rand -hex 32)" -e LOCKBOX_MASTER_KEY="$(openssl rand -hex 32)" \
  -e DATABASE_URL="postgres://backend:smoke@${name}-db:5432/raildock_production" \
  -e QUEUE_DATABASE_URL="postgres://backend:smoke@${name}-db:5432/raildock_production_queue" \
  -e CACHE_DATABASE_URL="postgres://backend:smoke@${name}-db:5432/raildock_production_cache" \
  -e CABLE_DATABASE_URL="postgres://backend:smoke@${name}-db:5432/raildock_production_cable" \
  -e DB_HOST="${name}-db" -e DB_USER=backend -e DB_PASSWORD=smoke "$image" >/dev/null
for _attempt in $(seq 1 90); do
  if docker exec "$name" curl -fsS http://localhost/api/health >/dev/null 2>&1; then
    docker exec "$name" test -s /rails/config/credentials.yml.enc
    docker exec "$name" test -s /rails/config/master.key
    exit 0
  fi
  sleep 2
done
docker logs "$name"
exit 1
