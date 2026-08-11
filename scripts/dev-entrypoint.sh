#!/bin/sh
# RailDock dev backend entrypoint (mounted by docker-compose.dev.yml).
#
# Boots the Rails server in development mode inside a container with the host
# source mounted at /rails, so code changes hot-reload via `bin/rails server`.
#
# Responsibilities:
#   1. Seed the production gems from the image into the bundle volume (first boot).
#   2. Install the development/test gem group into the bundle volume.
#   3. Wait for PostgreSQL.
#   4. Prepare the primary database and ensure the Solid Queue / Cache / Cable
#      schemas exist (mirrors docker/docker-entrypoint for production).
#   5. exec the CMD (Rails server).

set -e

# ── 1. Seed bundled gems (one-time) ─────────────────────────────────────────
if [ ! -d /usr/local/bundle/vendor/ruby ]; then
  echo "==> Seeding bundled gems from image..."
  cp -a /opt/bundle-seed/. /usr/local/bundle/
fi

# ── 2. Install dev/test gems ────────────────────────────────────────────────
cd /rails
bundle config set path /usr/local/bundle/vendor
bundle install --quiet

# ── 3. Wait for database ────────────────────────────────────────────────────
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-raildock}"
echo "==> Waiting for database at ${DB_HOST}:${DB_PORT}..."
attempt=0
until pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 30 ]; then
    echo "   Database not reachable — continuing anyway"
    break
  fi
  sleep 2
done
echo "==> Database is ready"

# ── 4. Prepare databases ────────────────────────────────────────────────────
# db:prepare creates the primary + Solid Queue/Cable databases and loads their
# schemas (development uses memory_store for cache and async for cable, so no
# cache/cable DB is configured in database.yml).
echo "==> Preparing databases..."
bin/rails db:prepare
echo "==> Databases ready"

# ── 5. Start the Rails server ───────────────────────────────────────────────
exec "$@"
