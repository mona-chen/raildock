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

ensure_user_and_key root
install_docker
install_dokku
# Dokku must be installed before the dokku user exists, so add the key after.
ensure_user_and_key dokku

log_info "Bootstrap complete. Return to RailDock and click Validate Server."
