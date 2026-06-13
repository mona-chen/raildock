#!/bin/bash
# RailDock Installer
# Usage:
#   curl -sSL https://raw.githubusercontent.com/mona-chen/raildock/main/install.sh | bash
#   curl -sSL .../install.sh | bash -s -- /opt/raildock
#   ./install.sh [install-dir] [update]
#
# Requirements: Docker 20+ (with Buildx for source builds)

set -e

# ── Config ────────────────────────────────────
RAILDOCK_VERSION="${RAILDOCK_VERSION:-latest}"
case "${1:-}" in
  update|upgrade) INSTALL_DIR="$(pwd)" ;;
  *)              INSTALL_DIR="${1:-$(pwd)}" ;;
esac
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
ENV_FILE="$INSTALL_DIR/.env"
DATA_DIR="$INSTALL_DIR/data"
NETWORK_NAME="raildock-network"
DB_VOLUME="raildock_postgres_data"
APP_PORT="${PORT:-8888}"
IMAGE="ghcr.io/mona-chen/raildock/raildock:${RAILDOCK_VERSION}"
BUILD_FROM_SOURCE="${BUILD_FROM_SOURCE:-0}"
REPO_URL="${RAILDOCK_REPO:-https://github.com/mona-chen/raildock.git}"

# ── Colors ────────────────────────────────────
B="\033[0;34m"
G="\033[0;32m"
Y="\033[1;33m"
R="\033[0;31m"
C="\033[0;36m"
N="\033[0m"

log_info()  { printf "${B}●${N} %s\n" "$1"; }
log_ok()    { printf "${G}✓${N} %s\n" "$1"; }
log_warn()  { printf "${Y}⚠${N} %s\n" "$1"; }
log_error() { printf "${R}✗${N} %s\n" "$1"; }
log_step()  { printf "\n${C}▶${N} %s\n" "$1"; }

print_banner() {
  printf "\n${B}╔══════════════════════════════════════════════════════════════╗${N}\n"
  printf "${B}║${N}                                                              ${B}║${N}\n"
  printf "${B}║${N}          ${G}⚡ RailDock Installation${N}                            ${B}║${N}\n"
  printf "${B}║${N}                                                              ${B}║${N}\n"
  printf "${B}╚══════════════════════════════════════════════════════════════╝${N}\n\n"
}

print_success() {
  local url="$1"
  printf "\n${G}╔══════════════════════════════════════════════════════════════╗${N}\n"
  printf "${G}║${N}                                                              ${G}║${N}\n"
  printf "${G}║${N}                ${G}🎉 RailDock is installed!${N}                          ${G}║${N}\n"
  printf "${G}║${N}                                                              ${G}║${N}\n"
  printf "${G}╚══════════════════════════════════════════════════════════════╝${N}\n\n"
  printf "  ${B}Dashboard:${N}     %s\n" "$url"
  printf "\n"
  printf "  ${B}Stop:${N}          cd %s && docker compose down\n" "$INSTALL_DIR"
  printf "  ${B}Start:${N}         cd %s && docker compose up -d\n" "$INSTALL_DIR"
  printf "  ${B}View logs:${N}     cd %s && docker compose logs -f\n" "$INSTALL_DIR"
  printf "  ${B}Update:${N}        cd %s && ./install.sh update\n\n" "$INSTALL_DIR"
  printf "  ${Y}Back up these files:${N}\n"
  printf "    ${B}%s/.env${N}\n" "$INSTALL_DIR"
  printf "    ${B}%s/backend/config/master.key${N}\n\n" "$INSTALL_DIR"
}

# ── Utilities ──────────────────────────────────
generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32 | tr -d "=+/\n" | cut -c1-32
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
  fi
}

generate_hex() {
  local len="$1"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$((len / 2))" | head -c "$len"
  else
    tr -dc 'a-f0-9' </dev/urandom | head -c "$len"
  fi
}

generate_jwt_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 64 | tr -d "=+/\n" | head -c 64
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 64
  fi
}

generate_ar_encryption_key() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32 | tr -d "=+/\n" | head -c 32
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
  fi
}

# ── Dokku / SSH helpers ───────────────────────
SSH_KEY_DIR="$INSTALL_DIR/data/dokku-ssh"

is_dokku_installed() {
  command -v dokku >/dev/null 2>&1
}

check_dokku() {
  if is_dokku_installed; then
    log_ok "Dokku $(dokku version | head -1) is installed"
    return 0
  fi

  install_dokku
}

install_dokku() {
  log_step "Installing Dokku..."
  if [ "$(uname)" != "Linux" ]; then
    log_error "Automatic Dokku installation is only supported on Linux"
    exit 1
  fi

  local detected_hostname
  detected_hostname=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "localhost")

  export DOKKU_TAG="${DOKKU_TAG:-v0.38.1}"
  export DOKKU_HOSTNAME="${DOKKU_HOSTNAME:-$detected_hostname}"
  export DOKKU_VHOST_ENABLE="${DOKKU_VHOST_ENABLE:-false}"
  export DOKKU_SKIP_KEY_FILE="true"

  log_info "Dokku version: $DOKKU_TAG"
  log_info "Dokku hostname: $DOKKU_HOSTNAME"

  curl -fsSL "https://raw.githubusercontent.com/dokku/dokku/${DOKKU_TAG}/bootstrap.sh" | bash

  # Stop the web installer if the package started it; we configure keys via CLI.
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop dokku-installer 2>/dev/null || true
    systemctl disable dokku-installer 2>/dev/null || true
  fi

  log_ok "Dokku installed"
}

ensure_dokku_plugins() {
  if ! is_dokku_installed; then
    return 0
  fi

  log_step "Ensuring Dokku datastore plugins are installed..."

  install_dokku_plugin() {
    local name="$1"
    local url="$2"
    if [ ! -d "/var/lib/dokku/plugins/enabled/$name" ]; then
      log_info "Installing $name plugin..."
      dokku plugin:install "$url" "$name" || log_warn "Failed to install $name plugin"
    fi
  }

  install_dokku_plugin "postgres" "https://github.com/dokku/dokku-postgres.git"
  install_dokku_plugin "redis"    "https://github.com/dokku/dokku-redis.git"
  install_dokku_plugin "mysql"    "https://github.com/dokku/dokku-mysql.git"
  install_dokku_plugin "mongo"    "https://github.com/dokku/dokku-mongo.git"

  # Patch postgres plugin if it ships with a broken default image
  POSTGRES_DOCKERFILE="/var/lib/dokku/plugins/enabled/postgres/Dockerfile"
  if [ -f "$POSTGRES_DOCKERFILE" ] && grep -q "postgres:18.3" "$POSTGRES_DOCKERFILE" 2>/dev/null; then
    log_info "Patching postgres plugin Dockerfile (18.3 → 16-alpine)..."
    echo 'FROM postgres:16-alpine' > "$POSTGRES_DOCKERFILE"
  fi

  # Patch mongo plugin if it ships with a broken default image
  MONGO_DOCKERFILE="/var/lib/dokku/plugins/enabled/mongo/Dockerfile"
  if [ -f "$MONGO_DOCKERFILE" ] && grep -q "mongo:8.2.7" "$MONGO_DOCKERFILE" 2>/dev/null; then
    log_info "Patching mongo plugin Dockerfile (8.2.7 → 7.0)..."
    echo 'FROM mongo:7.0' > "$MONGO_DOCKERFILE"
  fi

  log_ok "Dokku plugins ready"
}

configure_sshd_for_raildock() {
  if ! is_dokku_installed; then
    return 0
  fi

  # RailDock opens many short-lived SSH connections during one-click deploys.
  # Raise sshd's unauthenticated connection limits so bursts don't get dropped.
  local sshd_config="/etc/ssh/sshd_config"
  if [ -f "$sshd_config" ]; then
    if ! grep -qE "^MaxStartups\s+" "$sshd_config"; then
      echo "MaxStartups 100:30:200" >> "$sshd_config"
      log_ok "Raised sshd MaxStartups for RailDock deploy bursts"
      if command -v systemctl >/dev/null 2>&1; then
        systemctl reload sshd 2>/dev/null || true
      fi
    fi
  fi
}

generate_ssh_key() {
  mkdir -p "$SSH_KEY_DIR"
  chmod 700 "$SSH_KEY_DIR"
  if [ ! -f "$SSH_KEY_DIR/id_ed25519" ]; then
    ssh-keygen -t ed25519 -f "$SSH_KEY_DIR/id_ed25519" -N "" -C "raildock-$(hostname -s)" >/dev/null 2>&1
    log_ok "Generated Ed25519 SSH key for Dokku"
  else
    log_info "Using existing SSH key in $SSH_KEY_DIR"
  fi

  # The Rails container runs as UID/GID 1000. Ensure it can read the keys.
  chown -R 1000:1000 "$SSH_KEY_DIR" 2>/dev/null || chmod -R 755 "$SSH_KEY_DIR"
  chmod 600 "$SSH_KEY_DIR/id_ed25519"
  chmod 644 "$SSH_KEY_DIR/id_ed25519.pub"
}

register_ssh_key_with_dokku() {
  local pub_key="$SSH_KEY_DIR/id_ed25519.pub"
  if [ ! -f "$pub_key" ]; then
    log_error "SSH public key not found at $pub_key"
    return 1
  fi

  if ! is_dokku_installed; then
    log_warn "Cannot register SSH key: Dokku is not installed"
    return 1
  fi

  # Remove any previously registered RailDock key so the current key is always
  # the one Dokku accepts. This prevents fingerprint mismatches across reinstalls.
  if dokku ssh-keys:list 2>/dev/null | grep -q "raildock"; then
    dokku ssh-keys:remove raildock 2>/dev/null || true
    log_info "Removed previous RailDock SSH key from Dokku"
  fi

  dokku ssh-keys:add raildock "$pub_key"
  log_ok "Registered RailDock SSH key with Dokku"

  # HostEngine connects as root to run docker/network commands. Add the same
  # public key to root's authorized_keys so root auth doesn't fail and trigger
  # sshd per-source penalties that also drop dokku connections.
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  if ! grep -qF "$(cat "$pub_key")" /root/.ssh/authorized_keys 2>/dev/null; then
    cat "$pub_key" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    log_ok "Registered RailDock SSH key for root access"
  fi
}

configure_dokku_proxy() {
  if ! is_dokku_installed; then
    return 0
  fi

  local proxy_mode="${PROXY_MODE:-managed}"
  if [ "$proxy_mode" = "external" ]; then
    if [ -z "${EXTERNAL_PROXY_NETWORK:-}" ]; then
      log_error "PROXY_MODE=external requires EXTERNAL_PROXY_NETWORK"
      exit 1
    fi
    log_info "External proxy mode — leaving existing host proxy services untouched"
    return 0
  fi

  # Allow users to force nginx if they don't want Traefik.
  local proxy_type="${PROXY_TYPE:-traefik}"
  if [ "$proxy_type" != "traefik" ]; then
    log_info "PROXY_TYPE=$proxy_type — skipping Traefik default setup"
    return 0
  fi

  # Only switch to Traefik if the core traefik-vhosts plugin is present.
  if ! dokku plugin:list 2>/dev/null | grep -q "traefik-vhosts"; then
    log_warn "Traefik plugin not found — keeping Dokku's default proxy"
    return 0
  fi

  log_step "Configuring Traefik as the default proxy..."

  local current_proxy
  current_proxy=$(dokku proxy:report --global --proxy-global-type 2>/dev/null | tr -d '[:space:]' || true)
  if [ "$current_proxy" != "traefik" ]; then
    dokku proxy:set --global traefik
    log_ok "Set Traefik as the global default proxy"
  else
    log_info "Traefik is already the global default proxy"
  fi

  # Stop nginx to avoid port 80 conflicts with Traefik.
  if systemctl is-active --quiet nginx 2>/dev/null || systemctl is-enabled --quiet nginx 2>/dev/null; then
    dokku nginx:stop 2>/dev/null || true
    log_ok "Stopped nginx"
  fi

  # Ensure Traefik is running.
  if ! docker ps --filter "name=traefik-traefik-1" --format "{{.Names}}" | grep -q "traefik-traefik-1"; then
    dokku traefik:start
    log_ok "Started Traefik"
  else
    log_info "Traefik is already running"
  fi
}

detect_dokku_host() {
  # Prefer the explicit override, then host.docker.internal (works on Docker Desktop
  # and Docker 20.10+ Linux when extra_hosts is configured), then the public IP.
  if [ -n "${DOKKU_HOST:-}" ]; then
    echo "$DOKKU_HOST"
    return 0
  fi

  local public_ip
  public_ip=$(get_public_ip)
  if [ -n "$public_ip" ] && [ "$public_ip" != "127.0.0.1" ]; then
    echo "$public_ip"
    return 0
  fi

  echo "host.docker.internal"
}

create_local_server_record() {
  if ! is_dokku_installed; then
    log_warn "Skipping local server record: Dokku is not installed"
    return 0
  fi

  if [ ! -f "$SSH_KEY_DIR/id_ed25519" ]; then
    log_warn "Skipping local server record: SSH key not found"
    return 0
  fi

  local dokku_host
  dokku_host=$(detect_dokku_host)

  log_step "Creating local Dokku server record..."

  # Copy the key into the container temporarily so Rails can read it
  docker compose -f "$COMPOSE_FILE" cp "$SSH_KEY_DIR/id_ed25519" "raildock:/tmp/raildock-dokku-key" >/dev/null 2>&1 || {
    log_warn "Could not copy SSH key into RailDock container"
    return 1
  }

  docker compose -f "$COMPOSE_FILE" exec -T --user root raildock chmod 644 /tmp/raildock-dokku-key

  docker compose -f "$COMPOSE_FILE" exec -T raildock bin/rails runner "
    privkey = File.read('/tmp/raildock-dokku-key')
    server = Server.find_by(host: '$dokku_host')

    if server
      server.update!(
        name: 'Local Dokku',
        ssh_key: privkey,
        status: :disconnected,
        default_proxy: 'traefik',
        proxy_mode: '${PROXY_MODE:-managed}',
        external_proxy_network: '${EXTERNAL_PROXY_NETWORK:-}',
        external_proxy_http_entrypoint: '${EXTERNAL_PROXY_HTTP_ENTRYPOINT:-web}',
        external_proxy_https_entrypoint: '${EXTERNAL_PROXY_HTTPS_ENTRYPOINT:-websecure}',
        external_proxy_cert_resolver: '${EXTERNAL_PROXY_CERT_RESOLVER:-}',
        external_proxy_redirect_middleware: '${EXTERNAL_PROXY_REDIRECT_MIDDLEWARE:-}'
      )
      puts \"Updated server: #{server.name}\"
    else
      server = Server.create!(
        name: 'Local Dokku',
        host: '$dokku_host',
        ssh_key: privkey,
        status: :disconnected,
        default_proxy: 'traefik',
        proxy_mode: '${PROXY_MODE:-managed}',
        external_proxy_network: '${EXTERNAL_PROXY_NETWORK:-}',
        external_proxy_http_entrypoint: '${EXTERNAL_PROXY_HTTP_ENTRYPOINT:-web}',
        external_proxy_https_entrypoint: '${EXTERNAL_PROXY_HTTPS_ENTRYPOINT:-websecure}',
        external_proxy_cert_resolver: '${EXTERNAL_PROXY_CERT_RESOLVER:-}',
        external_proxy_redirect_middleware: '${EXTERNAL_PROXY_REDIRECT_MIDDLEWARE:-}'
      )
      puts \"Created server: #{server.name}\"
    end

    begin
      engine = DokkuEngine.new(server)
      result = engine.validate_connection
      if result[:success]
        proxy_type_result = engine.run('proxy:report --global --proxy-global-type')
        detected = proxy_type_result[:output].to_s.strip.presence
        detected ||= %w[traefik caddy haproxy openresty].find { |p| engine.run('proxy:report')[:output].to_s.downcase.include?(p) }
        detected ||= 'nginx'
        server.update!(
          status: :connected,
          dokku_version: result[:dokku_version],
          docker_version: result[:docker_version],
          os: result[:os],
          uptime: result[:uptime],
          default_proxy: detected,
          public_ip: result[:public_ip]
        )
        puts \"Validated connection (Dokku #{result[:dokku_version]})\"
      else
        server.update!(status: :error)
        puts \"Connection failed: #{result[:output]}\"
      end
    rescue => e
      server.update!(status: :error)
      puts \"Validation error: #{e.message}\"
    end
  "

  docker compose -f "$COMPOSE_FILE" exec -T --user root raildock rm -f /tmp/raildock-dokku-key

  log_ok "Local Dokku server record created"
}

get_public_ip() {
  local ip=""
  ip=$(curl -4s --connect-timeout 5 https://ifconfig.io 2>/dev/null)
  [ -z "$ip" ] && ip=$(curl -4s --connect-timeout 5 https://icanhazip.com 2>/dev/null)
  [ -z "$ip" ] && ip=$(curl -4s --connect-timeout 5 https://ipecho.net/plain 2>/dev/null)
  [ -z "$ip" ] && ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [ -z "$ip" ] && ip="127.0.0.1"
  echo "$ip"
}

get_public_url() {
  local host
  host=$(get_public_ip)
  if [ "$APP_PORT" = "80" ]; then
    echo "http://${host}"
  else
    echo "http://${host}:${APP_PORT}"
  fi
}

get_public_host() {
  local url="$1"
  url="${url#http://}"
  url="${url#https://}"
  url="${url%%/*}"
  echo "${url%%:*}"
}

# ── Checks ────────────────────────────────────
check_os() {
  local os
  os=$(uname -s)
  if [ "$os" = "Darwin" ]; then
    log_info "macOS detected — ensure Docker Desktop or Colima is running"
  elif [ "$os" != "Linux" ]; then
    log_error "Unsupported OS: $os (Linux required)"
    exit 1
  fi
}

install_docker() {
  log_step "Installing Docker..."
  if [ "$(uname)" != "Linux" ]; then
    log_error "Automatic Docker installation is only supported on Linux"
    log_info "Install Docker manually: https://docs.docker.com/get-docker/"
    exit 1
  fi

  curl -fsSL https://get.docker.com | bash
  systemctl enable docker 2>/dev/null || true
  systemctl start docker 2>/dev/null || true
  log_ok "Docker installed"
}

check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log_warn "Docker is not installed — installing automatically..."
    install_docker
  fi
  if ! docker info >/dev/null 2>&1; then
    log_error "Docker daemon is not running"
    if [ "$(uname)" = "Darwin" ]; then
      log_info "Start Docker Desktop or Colima:  colima start"
    else
      log_info "Start Docker:  sudo systemctl start docker"
    fi
    exit 1
  fi
  log_ok "Docker $(docker version --format '{{.Server.Version}}') is ready"
}

check_ports() {
  if command -v ss >/dev/null 2>&1 && ss -tulnp 2>/dev/null | grep -q ":${APP_PORT} "; then
    log_error "Port ${APP_PORT} is already in use — stop the conflicting service first"
    exit 1
  elif command -v lsof >/dev/null 2>&1 && lsof -Pi :"${APP_PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
    log_error "Port ${APP_PORT} is already in use"
    exit 1
  fi
  log_ok "Port ${APP_PORT} is available"
}

# ── Setup ─────────────────────────────────────
ensure_repo_files() {
  if [ -f "$COMPOSE_FILE" ] && [ -f "$INSTALL_DIR/Dockerfile" ] && grep -q "raildock" "$COMPOSE_FILE" 2>/dev/null; then
    log_info "Using existing RailDock files in $INSTALL_DIR"
    return 0
  fi

  log_info "Downloading RailDock files..."
  mkdir -p "$INSTALL_DIR"
  if command -v git >/dev/null 2>&1; then
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  else
    log_error "git is required but not installed"
    exit 1
  fi
  log_ok "RailDock files downloaded to $INSTALL_DIR"
}

check_existing_volume() {
  if docker volume inspect "$DB_VOLUME" >/dev/null 2>&1 && [ ! -f "$ENV_FILE" ]; then
    log_warn "PostgreSQL volume '$DB_VOLUME' already exists but $ENV_FILE is missing"
    log_warn "To keep existing data, restore your original .env file and re-run install.sh"
    log_warn "To start fresh, remove the volume with: docker volume rm $DB_VOLUME"
    exit 1
  fi
}

create_env() {
  if [ -f "$ENV_FILE" ] && grep -q "RAILS_MASTER_KEY" "$ENV_FILE" 2>/dev/null; then
    log_warn ".env exists — keeping existing credentials"
    return 0
  fi

  local pg_pass master_key jwt_secret ar_primary_key ar_deterministic_key ar_key_derivation_salt public_url public_host
  pg_pass=$(generate_password)

  if [ -f "$INSTALL_DIR/backend/config/master.key" ]; then
    master_key=$(tr -d '[:space:]' < "$INSTALL_DIR/backend/config/master.key")
    log_info "Using existing backend/config/master.key"
  else
    master_key=$(generate_hex 32)
  fi

  jwt_secret=$(generate_jwt_secret)
  ar_primary_key=$(generate_ar_encryption_key)
  ar_deterministic_key=$(generate_ar_encryption_key)
  ar_key_derivation_salt=$(generate_ar_encryption_key)
  lockbox_key=$(generate_hex 64)
  public_url="${RAILDOCK_PUBLIC_URL:-$(get_public_url)}"
  public_host="${RAILDOCK_PUBLIC_HOST:-$(get_public_host "$public_url")}"
  dokku_host="${DOKKU_HOST:-$(detect_dokku_host)}"

  cat > "$ENV_FILE" <<EOF
# RailDock Environment — generated by install.sh on $(date +%Y-%m-%d)
RAILS_ENV=production
PORT=${APP_PORT}
FRONTEND_URL=${public_url}
RAILDOCK_PUBLIC_URL=${public_url}
RAILDOCK_PUBLIC_HOST=${public_host}
DOKKU_HOST=${dokku_host}
TRAEFIK_ENABLE=${TRAEFIK_ENABLE:-false}
PROXY_MODE=${PROXY_MODE:-managed}
EXTERNAL_PROXY_NETWORK=${EXTERNAL_PROXY_NETWORK:-}
EXTERNAL_PROXY_HTTP_ENTRYPOINT=${EXTERNAL_PROXY_HTTP_ENTRYPOINT:-web}
EXTERNAL_PROXY_HTTPS_ENTRYPOINT=${EXTERNAL_PROXY_HTTPS_ENTRYPOINT:-websecure}
EXTERNAL_PROXY_CERT_RESOLVER=${EXTERNAL_PROXY_CERT_RESOLVER:-}
EXTERNAL_PROXY_REDIRECT_MIDDLEWARE=${EXTERNAL_PROXY_REDIRECT_MIDDLEWARE:-}
POSTGRES_PASSWORD=${pg_pass}
DATABASE_URL=postgres://raildock:${pg_pass}@db:5432/raildock_production
QUEUE_DATABASE_URL=postgres://raildock:${pg_pass}@db:5432/raildock_production_queue
CACHE_DATABASE_URL=postgres://raildock:${pg_pass}@db:5432/raildock_production_cache
CABLE_DATABASE_URL=postgres://raildock:${pg_pass}@db:5432/raildock_production_cable
RAILS_MASTER_KEY=${master_key}
JWT_SECRET_KEY=${jwt_secret}
LOCKBOX_MASTER_KEY=${lockbox_key}
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=${ar_primary_key}
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=${ar_deterministic_key}
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=${ar_key_derivation_salt}
EOF

  chmod 600 "$ENV_FILE"
  log_ok "Created $ENV_FILE with secure credentials"

  mkdir -p "$INSTALL_DIR/backend/config"
  echo "$master_key" > "$INSTALL_DIR/backend/config/master.key"
  chmod 600 "$INSTALL_DIR/backend/config/master.key"
  log_ok "Created backend/config/master.key"
}

create_credentials_file() {
  if [ -f "$INSTALL_DIR/backend/config/credentials.yml.enc" ]; then
    log_info "Rails credentials file already exists"
    return 0
  fi

  log_info "Creating fresh Rails credentials file..."

  # When building from source, build the image first so we can use it here.
  if [ "$BUILD_FROM_SOURCE" = "1" ]; then
    log_info "Building RailDock image for credentials creation..."
    docker build -t "$IMAGE" -f "$INSTALL_DIR/Dockerfile" "$INSTALL_DIR"
  fi

  # Run as root so we can write into the host-mounted config directory regardless
  # of its owner. The generated file is world-readable (0644) so the rails user
  # inside the production container can read it.
  docker run --rm --user root --entrypoint bash \
    -e RAILS_MASTER_KEY="$(tr -d '[:space:]' < "$INSTALL_DIR/backend/config/master.key")" \
    -v "$INSTALL_DIR/backend/config:/rails/config" \
    "$IMAGE" \
    -c 'cd /rails && ([ -f config/credentials.yml.enc ] || EDITOR=true bin/rails credentials:edit) && chmod 644 config/credentials.yml.enc'
  log_ok "Created backend/config/credentials.yml.enc"
}

create_network() {
  if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    log_ok "Network $NETWORK_NAME already exists"
  else
    docker network create "$NETWORK_NAME" 2>/dev/null || true
    log_ok "Created network $NETWORK_NAME"
  fi
}

# ── Main ──────────────────────────────────────
install_raildock() {
  print_banner

  log_step "Checking prerequisites..."
  check_os
  check_docker
  check_ports

  log_step "Checking Dokku..."
  check_dokku

  ensure_dokku_plugins
  configure_sshd_for_raildock

  log_step "Downloading configuration..."
  ensure_repo_files

  log_step "Generating SSH key for Dokku..."
  generate_ssh_key
  register_ssh_key_with_dokku
  configure_dokku_proxy

  log_step "Generating credentials..."
  check_existing_volume
  create_env
  create_network

  log_step "Preparing Rails credentials..."
  create_credentials_file

  log_step "Starting RailDock..."
  if [ "$BUILD_FROM_SOURCE" = "1" ]; then
    log_info "BUILD_FROM_SOURCE=1 — building image locally"
    RAILDOCK_VERSION="$RAILDOCK_VERSION" docker compose -f "$COMPOSE_FILE" up -d --build
  else
    docker pull "$IMAGE"
    log_ok "Pulled $IMAGE"
    RAILDOCK_VERSION="$RAILDOCK_VERSION" docker compose -f "$COMPOSE_FILE" up -d
  fi

  log_step "Waiting for RailDock to be ready..."
  local ready=false
  for i in $(seq 1 30); do
    if curl -sf "http://localhost:${APP_PORT}/api/health" >/dev/null 2>&1; then
      ready=true
      break
    fi
    sleep 2
    printf "."
  done
  echo
  if [ "$ready" = "true" ]; then
    log_ok "RailDock is healthy"
  else
    log_error "RailDock failed to become healthy after 60s"
    log_info "Debug: curl -v http://localhost:${APP_PORT}/api/health"
    log_info "Logs:  docker compose -f $COMPOSE_FILE logs"
    exit 1
  fi

  create_local_server_record

  local public_ip
  public_ip=$(get_public_ip)
  print_success "http://${public_ip}:${APP_PORT}"
}

fill_missing_env_vars() {
  local added=0

  if ! grep -q "^LOCKBOX_MASTER_KEY=" "$ENV_FILE" 2>/dev/null; then
    echo "LOCKBOX_MASTER_KEY=$(generate_hex 64)" >> "$ENV_FILE"
    added=1
  fi

  if ! grep -q "^ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=" "$ENV_FILE" 2>/dev/null; then
    echo "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$(generate_ar_encryption_key)" >> "$ENV_FILE"
    echo "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$(generate_ar_encryption_key)" >> "$ENV_FILE"
    echo "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$(generate_ar_encryption_key)" >> "$ENV_FILE"
    added=1
  fi

  if ! grep -q "^QUEUE_DATABASE_URL=" "$ENV_FILE" 2>/dev/null; then
    local pg_pass
    pg_pass=$(grep "^POSTGRES_PASSWORD=" "$ENV_FILE" | cut -d= -f2-)
    : "${pg_pass:=raildock}"
    echo "QUEUE_DATABASE_URL=postgres://raildock:${pg_pass}@db:5432/raildock_production_queue" >> "$ENV_FILE"
    echo "CACHE_DATABASE_URL=postgres://raildock:${pg_pass}@db:5432/raildock_production_cache" >> "$ENV_FILE"
    echo "CABLE_DATABASE_URL=postgres://raildock:${pg_pass}@db:5432/raildock_production_cable" >> "$ENV_FILE"
    added=1
  fi

  if [ "$added" = "1" ]; then
    log_ok "Added missing env vars to .env"
  fi
}

update_raildock() {
  log_step "Updating RailDock ${RAILDOCK_VERSION}..."
  if [ ! -f "$COMPOSE_FILE" ]; then
    log_error "RailDock does not appear to be installed in $INSTALL_DIR"
    exit 1
  fi
  fill_missing_env_vars
  if [ "$BUILD_FROM_SOURCE" = "1" ]; then
    docker compose -f "$COMPOSE_FILE" build --pull
  else
    docker compose -f "$COMPOSE_FILE" pull
  fi
  docker compose -f "$COMPOSE_FILE" up -d
  log_ok "RailDock updated"
}

# ── Entrypoint ────────────────────────────────
case "${1:-install}" in
  update|upgrade)
    update_raildock
    ;;
  *)
    install_raildock
    ;;
esac
