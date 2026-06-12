#!/bin/bash
# RailDock PostgreSQL restore script
#
# Usage:
#   ./scripts/restore.sh backups/raildock_production-20260101-120000.sql.gz
#
# This will drop and recreate the target database. Use with caution.

set -e

INSTALL_DIR="${INSTALL_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
ENV_FILE="${ENV_FILE:-$INSTALL_DIR/.env}"
BACKUP_FILE="$1"

if [ -z "$BACKUP_FILE" ]; then
  echo "ERROR: Backup file required"
  echo "Usage: $0 <backup-file.sql.gz>"
  exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: File not found: $BACKUP_FILE"
  exit 1
fi

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck source=/dev/null
  . "$ENV_FILE"
  set +a
fi

if [ -z "$DATABASE_URL" ]; then
  echo "ERROR: DATABASE_URL is not set. Source $ENV_FILE or set it manually."
  exit 1
fi

db_name=$(echo "$DATABASE_URL" | sed -n 's|.*/\([^?]*\)\(?.*\)\?$|\1|p')

echo "WARNING: This will destroy and recreate $db_name"
read -r -p "Are you sure? [y/N] " confirm
if [ "$confirm" != "y" ]; then
  echo "Restore cancelled"
  exit 0
fi

echo "Restoring $BACKUP_FILE -> $db_name"
if [[ "$BACKUP_FILE" == *.gz ]]; then
  gunzip -c "$BACKUP_FILE" | psql "$DATABASE_URL"
else
  psql "$DATABASE_URL" < "$BACKUP_FILE"
fi

echo "Restore complete"
