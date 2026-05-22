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

# Ensure public key is registered with Dokku (wraps it with sshcommand)
if [ -f "$SSH_DIR/id_ed25519.pub" ]; then
  mkdir -p "$DOKKU_HOME/.ssh"
  chmod 700 "$DOKKU_HOME/.ssh"

  PUB_KEY=$(cat "$SSH_DIR/id_ed25519.pub")

  # Use dokku ssh-keys:add so the key is properly wrapped with command="..."
  # instead of appending a raw key which would grant unrestricted shell access.
  if ! dokku ssh-keys:list 2>/dev/null | grep -Fq "$PUB_KEY"; then
    cp "$SSH_DIR/id_ed25519.pub" /tmp/raildock.pub
    dokku ssh-keys:add raildock /tmp/raildock.pub || true
    rm -f /tmp/raildock.pub
    echo "[raildock-init] Registered SSH key with Dokku"
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

# Configure Traefik to use raildock-bridge network
# Modify the traefik-vhosts template to use raildock-bridge network
# and ensure it can see all containers on the host

TRAEFIK_TEMPLATE="/var/lib/dokku/plugins/available/traefik-vhosts/templates/compose.yml.sigil"

if [ -f "$TRAEFIK_TEMPLATE" ]; then
  echo "[raildock-init] Configuring traefik to use raildock-bridge network..."

  # Use raildock-bridge network mode
  sed -i 's/networks: \["raildock"\]/network_mode: raildock-bridge/' "$TRAEFIK_TEMPLATE"

  # Add provider network flag to ensure traefik watches the raildock-bridge network
  sed -i 's/--providers.docker.network=bridge/--providers.docker.network=raildock-bridge/' "$TRAEFIK_TEMPLATE"

  echo "[raildock-init] Traefik template updated"
fi

# ── Configure Global Traefik Settings ─────────────────────────────

# Set the domain for traefik
DOKKU_DOMAIN="${DOKKU_HOSTNAME:-localhost}"
echo "[raildock-init] Setting traefik domain to $DOKKU_DOMAIN..."

# Set traefik api vhost
dokku traefik:set --global api-vhost "traefik.$DOKKU_DOMAIN" || true

# Set traefik log level
dokku traefik:set --global log-level "INFO" || true

# ── Set Global Proxy to Traefik ────────────────────────────────

echo "[raildock-init] Setting global proxy to traefik..."
dokku proxy:set --global traefik || true

# ── Start Traefik ────────────────────────────────

echo "[raildock-init] Starting traefik..."
dokku traefik:start || echo "[raildock-init] Traefik start attempted"

echo "[raildock-init] Dokku is ready for RailDock"