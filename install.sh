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
INSTALL_DIR="${1:-$(pwd)}"
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

check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker is not installed"
    log_info "Install: https://docs.docker.com/get-docker/"
    exit 1
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
  public_url="${RAILDOCK_PUBLIC_URL:-$(get_public_url)}"
  public_host="${RAILDOCK_PUBLIC_HOST:-$(get_public_host "$public_url")}"

  cat > "$ENV_FILE" <<EOF
# RailDock Environment — generated by install.sh on $(date +%Y-%m-%d)
RAILS_ENV=production
PORT=${APP_PORT}
FRONTEND_URL=${public_url}
RAILDOCK_PUBLIC_URL=${public_url}
RAILDOCK_PUBLIC_HOST=${public_host}
TRAEFIK_ENABLE=${TRAEFIK_ENABLE:-false}
POSTGRES_PASSWORD=${pg_pass}
DATABASE_URL=postgres://raildock:${pg_pass}@db:5432/raildock_production
QUEUE_DATABASE_URL=postgres://raildock:${pg_pass}@db:5432/raildock_production_queue
CACHE_DATABASE_URL=postgres://raildock:${pg_pass}@db:5432/raildock_production_cache
CABLE_DATABASE_URL=postgres://raildock:${pg_pass}@db:5432/raildock_production_cable
RAILS_MASTER_KEY=${master_key}
JWT_SECRET_KEY=${jwt_secret}
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

  log_step "Downloading configuration..."
  ensure_repo_files

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

  local public_ip
  public_ip=$(get_public_ip)
  print_success "http://${public_ip}:${APP_PORT}"
}

update_raildock() {
  log_step "Updating RailDock ${RAILDOCK_VERSION}..."
  if [ ! -f "$COMPOSE_FILE" ]; then
    log_error "RailDock does not appear to be installed in $INSTALL_DIR"
    exit 1
  fi
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
