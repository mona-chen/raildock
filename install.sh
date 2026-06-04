#!/bin/bash
# RailDock Installer — Single Image
# Usage: curl -sSL https://raw.githubusercontent.com/mona-chen/raildock/main/install.sh | bash
# Or download and run locally: ./install.sh
#
# Requirements: Docker 20+

set -e

# ── Config ────────────────────────────────────
RAILDOCK_VERSION="${RAILDOCK_VERSION:-latest}"
INSTALL_DIR="${INSTALL_DIR:-$(pwd)}"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
NETWORK_NAME="raildock-network"
ENV_FILE="$INSTALL_DIR/.env"
DATA_DIR="$INSTALL_DIR/data"
DB_VOLUME="raildock_postgres_data"
APP_PORT="${PORT:-80}"

# ── Colors ────────────────────────────────────
B="\033[0;34m"
G="\033[0;32m"
Y="\033[1;33m"
R="\033[0;31m"
N="\033[0m"

log_info()  { printf "${B}●${N} %s\n" "$1"; }
log_ok()    { printf "${G}✓${N} %s\n" "$1"; }
log_warn()  { printf "${Y}⚠${N} %s\n" "$1"; }
log_error() { printf "${R}✗${N} %s\n" "$1"; }
log_step()  { printf "\n${C}▶${N} %s\n" "$1"; }
C="\033[0;36m"

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
  printf "  ${B}Dashboard:${N}     http://%s\n" "$url"
  printf "\n"
  printf "  ${B}Stop:${N}          docker compose -f %s down\n" "$COMPOSE_FILE"
  printf "  ${B}Start:${N}        docker compose -f %s up -d\n" "$COMPOSE_FILE"
  printf "  ${B}View logs:${N}    docker compose -f %s logs -f\n" "$COMPOSE_FILE"
  printf "  ${B}Update:${N}       ./install.sh update\n\n" "$COMPOSE_FILE"
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
  # Generates N hex chars (2 chars per byte)
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
download_compose_file() {
  # If docker-compose.yml exists locally, skip download
  if [ -f "$COMPOSE_FILE" ] && grep -q "raildock" "$COMPOSE_FILE" 2>/dev/null; then
    log_info "Using existing docker-compose.yml"
    return 0
  fi

  log_info "Downloading docker-compose.yml..."
  local tag_url="https://raw.githubusercontent.com/mona-chen/raildock/main/docker-compose.yml"
  if [ "$RAILDOCK_VERSION" != "latest" ]; then
    local version="${RAILDOCK_VERSION#v}"
    tag_url="https://raw.githubusercontent.com/mona-chen/raildock/v${version}/docker-compose.yml"
  fi
  if curl -fsSL "$tag_url" -o "$COMPOSE_FILE"; then
    log_ok "Downloaded docker-compose.yml"
  else
    log_error "Failed to download docker-compose.yml"
    exit 1
  fi
}

create_env() {
  if [ -f "$ENV_FILE" ] && grep -q "RAILS_MASTER_KEY" "$ENV_FILE" 2>/dev/null; then
    log_warn ".env exists — keeping existing credentials"
    return 0
  fi

  local pg_pass master_key jwt_secret ar_primary_key ar_deterministic_key ar_key_derivation_salt public_url
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

  cat > "$ENV_FILE" <<EOF
# RailDock Environment — generated by install.sh on $(date +%Y-%m-%d)
RAILS_ENV=production
PORT=${APP_PORT}
FRONTEND_URL=${public_url}
RAILDOCK_PUBLIC_URL=${public_url}
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

  # Write master.key for image builds (if building locally)
  mkdir -p "$INSTALL_DIR/backend/config"
  echo "$master_key" > "$INSTALL_DIR/backend/config/master.key"
  chmod 600 "$INSTALL_DIR/backend/config/master.key"
  log_ok "Created backend/config/master.key"
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
  download_compose_file

  log_step "Generating credentials..."
  create_env
  create_network

  log_step "Starting RailDock..."
  docker compose -f "$COMPOSE_FILE" up -d --build --pull always

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
  print_success "$public_ip:${APP_PORT}"
}

update_raildock() {
  log_step "Updating RailDock ${RAILDOCK_VERSION}..."
  docker compose -f "$COMPOSE_FILE" pull
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
