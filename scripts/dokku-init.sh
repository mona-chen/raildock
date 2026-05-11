#!/bin/bash
# RailDock Dokku Init — runs inside the Dokku container on startup
# Generates SSH keys and configures Dokku for zero-config deployments

set -e

SSH_DIR="/data/dokku-ssh"
DOKKU_USER="dokku"
DOKKU_HOME="/home/dokku"

echo "[raildock-init] Checking SSH key setup..."

# Generate SSH key pair if missing
if [ ! -f "$SSH_DIR/id_ed25519" ]; then
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"
  ssh-keygen -t ed25519 -f "$SSH_DIR/id_ed25519" -N "" -C "raildock" >/dev/null 2>&1
  echo "[raildock-init] Generated new Ed25519 SSH key pair"
fi

# Ensure public key is in Dokku's authorized_keys
if [ -f "$SSH_DIR/id_ed25519.pub" ]; then
  mkdir -p "$DOKKU_HOME/.ssh"
  chmod 700 "$DOKKU_HOME/.ssh"

  PUB_KEY=$(cat "$SSH_DIR/id_ed25519.pub")

  # Check if key already present (avoid duplicates)
  if ! grep -Fq "$PUB_KEY" "$DOKKU_HOME/.ssh/authorized_keys" 2>/dev/null; then
    # Dokku wraps authorized_keys entries with sshcommand for safety
    echo "$PUB_KEY" >> "$DOKKU_HOME/.ssh/authorized_keys"
    chmod 600 "$DOKKU_HOME/.ssh/authorized_keys"
    chown -R "$DOKKU_USER:$DOKKU_USER" "$DOKKU_HOME/.ssh"
    echo "[raildock-init] Added SSH key to Dokku authorized_keys"
  fi
fi

# Ensure Dokku's sshcommand wrapper exists
if [ ! -f "$DOKKU_HOME/.sshcommand" ]; then
  echo '/usr/bin/dokku' > "$DOKKU_HOME/.sshcommand"
  chown "$DOKKU_USER:$DOKKU_USER" "$DOKKU_HOME/.sshcommand"
fi

# ── Datastore Plugins ──────────────────────────────────────
# These plugins are required for RailDock database/cache services

install_plugin() {
  local name="$1"
  local url="$2"
  if [ ! -d "/var/lib/dokku/plugins/enabled/$name" ]; then
    echo "[raildock-init] Installing $name plugin..."
    dokku plugin:install "$url" "$name" || true
  fi
}

install_plugin "postgres" "https://github.com/dokku/dokku-postgres.git"
install_plugin "redis"    "https://github.com/dokku/dokku-redis.git"
install_plugin "mysql"    "https://github.com/dokku/dokku-mysql.git"
install_plugin "mongo"    "https://github.com/dokku/dokku-mongo.git"

# Fix broken postgres plugin Dockerfile (ships with non-existent postgres:18.3)
POSTGRES_DOCKERFILE="/var/lib/dokku/plugins/enabled/postgres/Dockerfile"
if [ -f "$POSTGRES_DOCKERFILE" ]; then
  if grep -q "postgres:18.3" "$POSTGRES_DOCKERFILE" 2>/dev/null; then
    echo "[raildock-init] Patching postgres plugin Dockerfile (18.3 → 16-alpine)..."
    echo 'FROM postgres:16-alpine' > "$POSTGRES_DOCKERFILE"
  fi
fi

# Fix mongo plugin Dockerfile (8.2.7 has corrupted libcurl layer on some platforms)
MONGO_DOCKERFILE="/var/lib/dokku/plugins/enabled/mongo/Dockerfile"
if [ -f "$MONGO_DOCKERFILE" ]; then
  if grep -q "mongo:8.2.7" "$MONGO_DOCKERFILE" 2>/dev/null; then
    echo "[raildock-init] Patching mongo plugin Dockerfile (8.2.7 → 7.0)..."
    echo 'FROM mongo:7.0' > "$MONGO_DOCKERFILE"
  fi
fi

# ── Operational Plugins ────────────────────────────────────
# These plugins unlock existing RailDock UI features

install_plugin "letsencrypt"  "https://github.com/dokku/dokku-letsencrypt.git"
install_plugin "redirect"     "https://github.com/dokku/dokku-redirect.git"
install_plugin "maintenance"  "https://github.com/dokku/dokku-maintenance.git"

echo "[raildock-init] Dokku is ready for RailDock"
