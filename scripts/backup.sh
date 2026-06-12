#!/bin/bash
# RailDock PostgreSQL backup script
#
# Usage:
#   ./scripts/backup.sh                    # backup all RailDock databases
#   BACKUPS_DIR=/backups ./scripts/backup.sh
#   BACKUP_RETENTION_DAYS=7 ./scripts/backup.sh
#
# This is designed to run either on the Docker host or inside the backup
# container defined in docker-compose.yml.

set -e

INSTALL_DIR="${INSTALL_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
ENV_FILE="${ENV_FILE:-$INSTALL_DIR/.env}"
BACKUPS_DIR="${BACKUPS_DIR:-$INSTALL_DIR/backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  set -a
  # shellcheck source=/dev/null
  . "$ENV_FILE"
  set +a
fi

if [ -z "$DATABASE_URL" ]; then
  echo "ERROR: DATABASE_URL is not set. Source $ENV_FILE or set it manually."
  exit 1
fi

mkdir -p "$BACKUPS_DIR"

db_name=$(echo "$DATABASE_URL" | sed -n 's|.*/\([^?]*\)\(?.*\)\?$|\1|p')

backup_db() {
  local url="$1"
  local name="$2"
  local file="$BACKUPS_DIR/${name}-${TIMESTAMP}.sql.gz"

  echo "Backing up $name -> $file"
  pg_dump "$url" --clean --if-exists | gzip > "$file"
  echo "  $(du -h "$file" | cut -f1)"
}

backup_db "$DATABASE_URL" "$db_name"

for var in QUEUE_DATABASE_URL CACHE_DATABASE_URL CABLE_DATABASE_URL; do
  url="${!var}"
  if [ -n "$url" ]; then
    name=$(echo "$url" | sed -n 's|.*/\([^?]*\)\(?.*\)\?$|\1|p')
    backup_db "$url" "$name"
  fi
done

if [ "$RETENTION_DAYS" -gt 0 ]; then
  echo "Removing backups older than $RETENTION_DAYS days..."
  find "$BACKUPS_DIR" -type f -name "*.sql.gz" -mtime +"$RETENTION_DAYS" -delete
fi

echo "Backup complete: $BACKUPS_DIR"
