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

install_dokku() {
  if command -v dokku >/dev/null 2>&1; then
    log_info "Dokku already installed: $(dokku version)"
    return 0
  fi

  if [ "${INSTALL_DOKKU:-1}" != "1" ]; then
    log_info "INSTALL_DOKKU is not 1; skipping Dokku installation"
    return 0
  fi

  log_info "Installing Dokku..."
  export DOKKU_TAG="${DOKKU_TAG:-v0.38.1}"
  export DOKKU_VHOST_ENABLE="${DOKKU_VHOST_ENABLE:-false}"
  export DOKKU_SKIP_KEY_FILE="true"
  curl -fsSL "https://raw.githubusercontent.com/dokku/dokku/${DOKKU_TAG}/bootstrap.sh" | bash
}

configure_sshd
ensure_user_and_key root
install_docker
install_dokku
ensure_dokku_plugins
ensure_builder_binaries
# Dokku must be installed before the dokku user exists, so add the key after.
ensure_user_and_key dokku

log_info "Bootstrap complete. Return to RailDock and click Validate Server."
