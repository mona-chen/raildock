#!/bin/bash
set -e

# RailDock remote server bootstrap script.
# Run this as root on the Dokku host you want RailDock to manage.
#
# Usage:
#   curl -fsSL https://<raildock-host>/bootstrap.sh | bash -s -- '<org-public-key>'

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root" >&2
  exit 1
fi

PUBLIC_KEY="${1:-}"
PROXY_MODE="${PROXY_MODE:-managed}"

if [ -z "$PUBLIC_KEY" ]; then
  echo "Usage: $0 '<ssh-public-key>'" >&2
  exit 1
fi

case "$PUBLIC_KEY" in
  ssh-ed25519*|ssh-rsa*|ssh-ecdsa*|ssh-dss*) ;;
  *) echo "Invalid SSH public key format" >&2; exit 1 ;;
esac

log_info() { echo "==> $1"; }
log_warn() { echo "==> WARNING: $1"; }

configure_sshd() {
  local sshd_config="/etc/ssh/sshd_config"
  if [ -f "$sshd_config" ] && ! grep -qE "^MaxStartups\\s+" "$sshd_config"; then
    echo "MaxStartups 100:30:200" >> "$sshd_config"
    if command -v systemctl >/dev/null 2>&1; then
      systemctl reload sshd 2>/dev/null || true
    fi
    log_info "Raised sshd MaxStartups for deploy bursts"
  fi
}

ensure_dokku_plugins() {
  if ! command -v dokku >/dev/null 2>&1; then
    return 0
  fi

  install_plugin() {
    local name="$1"
    local url="$2"
    if [ ! -d "/var/lib/dokku/plugins/enabled/$name" ]; then
      log_info "Installing Dokku $name plugin..."
      dokku plugin:install "$url" "$name" || log_warn "Failed to install $name plugin"
    fi
  }

  install_plugin "postgres" "https://github.com/dokku/dokku-postgres.git"
  install_plugin "redis"    "https://github.com/dokku/dokku-redis.git"
  install_plugin "mysql"    "https://github.com/dokku/dokku-mysql.git"
  install_plugin "mongo"    "https://github.com/dokku/dokku-mongo.git"
}

ensure_builder_binaries() {
  if ! command -v docker >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v nixpacks >/dev/null 2>&1; then
    log_info "Installing nixpacks..."
    if bash -c "$(curl -fsSL https://raw.githubusercontent.com/railwayapp/nixpacks/master/install.sh)"; then
      log_info "nixpacks installed"
    else
      log_warn "Failed to install nixpacks"
    fi
  fi

  if ! command -v railpack >/dev/null 2>&1; then
    log_info "Installing railpack..."
    if curl -fsSL https://railpack.com/install.sh -o /tmp/raildock-railpack-install.sh \
      && bash /tmp/raildock-railpack-install.sh --bin-dir /usr/local/bin --yes; then
      log_info "railpack installed"
    else
      log_warn "Failed to install railpack"
    fi
    rm -f /tmp/raildock-railpack-install.sh
  fi

  if command -v railpack >/dev/null 2>&1; then
    if ! docker inspect buildkit >/dev/null 2>&1; then
      docker run --privileged -d --restart unless-stopped --name buildkit moby/buildkit:latest >/dev/null
      log_info "Started Railpack BuildKit container"
    elif [ "$(docker inspect -f '{{.State.Running}}' buildkit 2>/dev/null)" != "true" ]; then
      docker start buildkit >/dev/null
      log_info "Started existing BuildKit container"
    fi

    if [ -f /etc/default/dokku ]; then
      if grep -q '^export BUILDKIT_HOST=' /etc/default/dokku; then
        sed -i "s|^export BUILDKIT_HOST=.*|export BUILDKIT_HOST='docker-container://buildkit'|" /etc/default/dokku
      else
        echo "export BUILDKIT_HOST='docker-container://buildkit'" >> /etc/default/dokku
      fi
    fi
  fi
}

ensure_user_and_key() {
  local user="$1"
  local home

  if id "$user" >/dev/null 2>&1; then
    home=$(eval echo "~$user")
  else
    log_info "User $user does not exist; skipping key installation for $user"
    return 0
  fi

  mkdir -p "$home/.ssh"
  chmod 700 "$home/.ssh"

  if ! grep -qF "$PUBLIC_KEY" "$home/.ssh/authorized_keys" 2>/dev/null; then
    printf '%s\n' "$PUBLIC_KEY" >> "$home/.ssh/authorized_keys"
    log_info "Added public key to $home/.ssh/authorized_keys"
  else
    log_info "Public key already present for $user"
  fi

  chmod 600 "$home/.ssh/authorized_keys"
  chown -R "$user:$user" "$home/.ssh" 2>/dev/null || true
}

register_dokku_key() {
  # Dokku routes `ssh dokku@host <subcommand>` through the sshcommand wrapper
  # that `dokku ssh-keys:add` writes into authorized_keys (a command="..."
  # prefix invoking /usr/bin/dokku). Appending a raw key would grant the dokku
  # user a plain bash shell and break all DokkuEngine command routing, so the
  # key must be registered via Dokku's own command.
  if ! command -v dokku >/dev/null 2>&1; then
    log_warn "dokku binary not found; cannot register key with sshcommand wrapper"
    return 1
  fi

  # Remove any raw (non-wrapped) occurrence of this key from previous
  # bootstraps. A raw line would be matched by sshd before the sshcommand
  # wrapper and bypass Dokku's command routing. Wrapped entries (starting
  # with command=) are left intact.
  local auth_keys="/home/dokku/.ssh/authorized_keys"
  if [ -f "$auth_keys" ] && grep -qF "$PUBLIC_KEY" "$auth_keys"; then
    local tmp_auth
    tmp_auth=$(mktemp /tmp/raildock-authorized_keys.XXXXXX)
    awk -v key="$PUBLIC_KEY" 'index($0, key) == 0 || $0 ~ /^command=/ { print }' "$auth_keys" > "$tmp_auth"
    cat "$tmp_auth" > "$auth_keys"
    rm -f "$tmp_auth"
    chmod 600 "$auth_keys"
    chown dokku:dokku "$auth_keys"
    log_info "Removed raw (non-wrapped) key from dokku authorized_keys"
  fi

  local tmp_key
  tmp_key=$(mktemp /tmp/raildock-ssh-key.XXXXXX)
  printf '%s\n' "$PUBLIC_KEY" > "$tmp_key"

  # sshcommand list reports FINGERPRINT NAME="..." — never the raw key — so
  # match on the registration name instead of the key material.
  if ! dokku ssh-keys:list 2>/dev/null | grep -q "raildock"; then
    if dokku ssh-keys:add raildock "$tmp_key" 2>/dev/null; then
      log_info "Registered public key with Dokku (sshcommand-wrapped)"
    else
      log_warn "dokku ssh-keys:add failed; the dokku user will not route RailDock commands"
    fi
  else
    log_info "Public key already registered with Dokku"
  fi

  rm -f "$tmp_key"
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log_info "Docker already installed: $(docker --version)"
    return 0
  fi

  log_info "Installing Docker Engine..."
  curl -fsSL https://get.docker.com | bash
  systemctl enable docker || true
  systemctl start docker || true
}

prepare_port_80() {
  # Dokku's package installs nginx and tries to start it on port 80.
  # If another service is already bound to port 80, dpkg will fail.
  local listener
  listener=$(ss -tlnp 2>/dev/null | awk '/:80 / {print $0}' | head -1)
  if [ -z "$listener" ]; then
    return 0
  fi

  if echo "$listener" | grep -qE '"nginx"'; then
    log_info "Port 80 already in use by nginx; continuing"
    return 0
  fi

  local proc
  proc=$(echo "$listener" | grep -oE '"[^"]+"' | head -1 | tr -d '"')

  # Existing reverse proxies (Coolify/Traefik/Caddy) should not be killed.
  if echo "$proc" | grep -qiE 'traefik|caddy'; then
    if [ "$PROXY_MODE" = "external" ]; then
      log_info "Port 80 is in use by $proc; external proxy mode enabled, leaving it in place"
      return 0
    fi
    log_warn "Port 80 is in use by $proc. Run with PROXY_MODE=external to reuse it, or stop it first."
    exit 1
  fi

  if [ "$PROXY_MODE" = "external" ]; then
    log_info "Port 80 is in use by $proc; external proxy mode does not need port 80"
    return 0
  fi

  log_warn "Port 80 is in use by $proc; stopping it so Dokku's nginx can start"

  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "$proc" 2>/dev/null || true
    systemctl disable "$proc" 2>/dev/null || true
  fi

  if command -v fuser >/dev/null 2>&1; then
    fuser -k 80/tcp 2>/dev/null || true
  fi
}

block_service_starts() {
  # Prevent dpkg from starting nginx (or any other service) during package install.
  # This is needed when an existing reverse proxy already owns port 80/443.
  printf '%s\n' '#!/bin/sh' 'exit 101' > /usr/sbin/policy-rc.d
  chmod +x /usr/sbin/policy-rc.d
}

unblock_service_starts() {
  rm -f /usr/sbin/policy-rc.d
}

install_dokku() {
  if command -v dokku >/dev/null 2>&1; then
    log_info "Dokku already installed: $(dokku version)"
    return 0
  fi

  if [ "${INSTALL_DOKKU:-1}" != "1" ]; then
    log_info "INSTALL_DOKKU is not 1; skipping Dokku installation"
    return 0
  fi

  log_info "Installing Dokku (PROXY_MODE=$PROXY_MODE)..."
  export DEBIAN_FRONTEND=noninteractive
  export DOKKU_TAG="${DOKKU_TAG:-v0.38.1}"
  export DOKKU_VHOST_ENABLE="${DOKKU_VHOST_ENABLE:-false}"
  export DOKKU_SKIP_KEY_FILE="true"

  if [ "$PROXY_MODE" = "external" ]; then
    block_service_starts
  fi

  curl -fsSL "https://raw.githubusercontent.com/dokku/dokku/${DOKKU_TAG}/bootstrap.sh" | bash

  if [ "$PROXY_MODE" = "external" ]; then
    unblock_service_starts
  fi
}

configure_dokku_proxy() {
  if ! command -v dokku >/dev/null 2>&1; then
    return 0
  fi

  if [ "$PROXY_MODE" = "external" ]; then
    log_info "Configuring external proxy mode — Dokku will not manage nginx/Traefik"
    # Stop and mask nginx so it does not try to bind port 80/443.
    systemctl stop nginx 2>/dev/null || true
    systemctl mask nginx 2>/dev/null || true
    dokku proxy:set --global none 2>/dev/null || true
    return 0
  fi

  # Default managed mode: ensure nginx is unmasked so Dokku can use it.
  systemctl unmask nginx 2>/dev/null || true
}

configure_sshd
ensure_user_and_key root
install_docker
prepare_port_80
install_dokku
configure_dokku_proxy
ensure_dokku_plugins
ensure_builder_binaries
# Dokku must be installed before the dokku user exists, so add the key after.
register_dokku_key

log_info "Bootstrap complete. Return to RailDock and click Validate Server."
