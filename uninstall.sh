#!/bin/bash
# RailDock Uninstall Script
# Usage: bash uninstall.sh [--keep-data] [--keep-env]
#   --keep-data    Keep Docker volumes and data directories
#   --keep-env     Keep .env file and credentials

set -e

RAILDOCK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$RAILDOCK_DIR/docker-compose.yml"
ENV_FILE="$RAILDOCK_DIR/.env"
DATA_DIR="$RAILDOCK_DIR/data"
SSH_KEY_DIR="$DATA_DIR/dokku-ssh"
NETWORK_NAME="raildock"
COMPOSE_PROJECT_NAME="raildock"

# ── Colors ───────────────────────────────────
B="\033[0;34m"
G="\033[0;32m"
Y="\033[1;33m"
R="\033[0;31m"
C="\033[0;36m"
N="\033[0m"

# ── Options ────────────────────────────────────
KEEP_DATA=false
KEEP_ENV=false
FORCE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --keep-data)
      KEEP_DATA=true
      shift
      ;;
    --keep-env)
      KEEP_ENV=true
      shift
      ;;
    --force|-f)
      FORCE=true
      shift
      ;;
    --help|-h)
      echo "RailDock Uninstall Script"
      echo ""
      echo "Usage: bash uninstall.sh [options]"
      echo ""
      echo "Options:"
      echo "  --keep-data    Keep Docker volumes and data directories"
      echo "  --keep-env     Keep .env file and credentials"
      echo "  --force, -f    Skip confirmation prompts"
      echo "  --help, -h     Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ── Helpers ───────────────────────────────────
log_info()  { printf "${B}●${N} %s\n" "$1"; }
log_ok()    { printf "${G}✓${N} %s\n" "$1"; }
log_warn()  { printf "${Y}⚠${N} %s\n" "$1"; }
log_error() { printf "${R}✗${N} %s\n" "$1"; }
log_step()  { printf "\n${C}▶${N} %s\n" "$1"; }

confirm() {
  local prompt="$1"
  local default="${2:-n}"
  
  if [ "$FORCE" = true ]; then
    return 0
  fi
  
  if [ "$default" = "y" ]; then
    prompt="$prompt [Y/n] "
  else
    prompt="$prompt [y/N] "
  fi
  
  read -p "$prompt" -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]] || [[ $REPLY = "" && "$default" = "y" ]]
}

is_stack_running() {
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qE "^${COMPOSE_PROJECT_NAME}-"
}

print_banner() {
  printf "\n${R}╔══════════════════════════════════════════════════════════════╗${N}\n"
  printf "${R}║${N}                                                              ${R}║${N}\n"
  printf "${R}║${N}          ${Y}⚡ RailDock Uninstall${N}                                ${R}║${N}\n"
  printf "${R}║${N}                                                              ${R}║${N}\n"
  printf "${R}╚══════════════════════════════════════════════════════════════╝${N}\n\n"
}

# ── Pre-flight Checks ─────────────────────────
check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log_warn "Docker is not installed — nothing to uninstall"
    exit 0
  fi

  if ! docker info >/dev/null 2>&1; then
    log_warn "Docker daemon is not running"
    exit 0
  fi
}

# ── Stop Services ──────────────────────────────
stop_services() {
  log_step "Stopping RailDock services..."
  
  if is_stack_running; then
    docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true
    log_ok "Services stopped"
  else
    log_info "No running services found"
  fi
  
  # Also try docker-compose (older versions)
  docker-compose -f "$COMPOSE_FILE" down 2>/dev/null || true
}

# ── Remove Containers ───────────────────────────
remove_containers() {
  log_step "Removing containers..."
  
  # Remove RailDock containers
  local containers=$(docker ps -a --format '{{.Names}}' | grep "^${COMPOSE_PROJECT_NAME}-" 2>/dev/null || true)
  
  if [ -n "$containers" ]; then
    echo "$containers" | xargs docker rm -f 2>/dev/null || true
    log_ok "RailDock containers removed"
  else
    log_info "No containers to remove"
  fi
  
  # Clean up any orphaned containers
  local orphaned=$(docker ps -a --format '{{.Names}}' | grep -E "^raildock-" 2>/dev/null || true)
  if [ -n "$orphaned" ]; then
    echo "$orphaned" | xargs docker rm -f 2>/dev/null || true
    log_info "Cleaned up orphaned containers"
  fi
}

# ── Remove Images ──────────────────────────────
remove_images() {
  log_step "Removing RailDock images..."
  
  # Get image names from compose file
  local images=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "^raildock-|^${COMPOSE_PROJECT_NAME}_" 2>/dev/null || true)
  
  if [ -n "$images" ]; then
    if confirm "Remove RailDock Docker images?" "n"; then
      echo "$images" | xargs docker rmi -f 2>/dev/null || true
      log_ok "RailDock images removed"
    else
      log_info "Skipped image removal"
    fi
  else
    log_info "No RailDock images found"
  fi
}

# ── Remove Volumes ─────────────────────────────
remove_volumes() {
  if [ "$KEEP_DATA" = true ]; then
    log_info "Keeping data volumes (--keep-data)"
    return 0
  fi

  log_step "Removing Docker volumes..."
  
  # Check for RailDock volumes
  local volumes=$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E "^${COMPOSE_PROJECT_NAME}_|^raildock_" || true)
  
  if [ -n "$volumes" ]; then
    if confirm "⚠️  This will DELETE all data (databases, uploads, etc.)!" "n"; then
      echo "$volumes" | xargs docker volume rm 2>/dev/null || true
      log_ok "Docker volumes removed"
    else
      log_info "Keeping volumes"
    fi
  else
    log_info "No RailDock volumes found"
  fi
  
  # Also clean up named volumes from compose file
  docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E "(postgres_data|rails_storage|dokku_data|letsencrypt)" | while read -r vol; do
    if confirm "Remove volume: $vol?" "n"; then
      docker volume rm "$vol" 2>/dev/null || true
    fi
  done
}

# ── Remove Networks ────────────────────────────
remove_networks() {
  log_step "Removing Docker networks..."
  
  # Remove RailDock network
  if docker network ls --format '{{.Name}}' 2>/dev/null | grep -q "^${NETWORK_NAME}$"; then
    docker network rm "$NETWORK_NAME" 2>/dev/null || true
    log_ok "Network '$NETWORK_NAME' removed"
  fi
  
  # Clean up any bridge networks
  if docker network ls --format '{{.Name}}' 2>/dev/null | grep -q "^${NETWORK_NAME}-bridge$"; then
    docker network rm "${NETWORK_NAME}-bridge" 2>/dev/null || true
  fi
}

# ── Remove Data Directory ───────────────────────
remove_data_dir() {
  if [ "$KEEP_DATA" = true ]; then
    log_info "Keeping data directory (--keep-data)"
    return 0
  fi

  log_step "Removing data directory..."
  
  if [ -d "$DATA_DIR" ]; then
    if confirm "Remove $DATA_DIR (SSH keys, Dokku data)?" "n"; then
      rm -rf "$DATA_DIR"
      log_ok "Data directory removed"
    else
      log_info "Keeping data directory"
    fi
  else
    log_info "No data directory found"
  fi
}

# ── Remove SSH Keys ────────────────────────────
remove_ssh_keys() {
  if [ -d "$SSH_KEY_DIR" ]; then
    if confirm "Remove SSH keys in $SSH_KEY_DIR?" "n"; then
      rm -rf "$SSH_KEY_DIR"
      log_ok "SSH keys removed"
    else
      log_info "Keeping SSH keys"
    fi
  fi
}

# ── Remove Environment File ───────────────────
remove_env_file() {
  if [ "$KEEP_ENV" = true ]; then
    log_info "Keeping .env file (--keep-env)"
    return 0
  fi

  if [ -f "$ENV_FILE" ]; then
    if confirm "Remove $ENV_FILE (contains credentials)?" "n"; then
      rm -f "$ENV_FILE"
      log_ok ".env file removed"
    else
      log_info "Keeping .env file"
    fi
  fi
}

# ── Clean Docker System ────────────────────────
clean_docker_system() {
  log_step "Cleaning up Docker system..."
  
  # Remove stopped containers
  docker container prune -f 2>/dev/null || true
  
  # Remove dangling images
  docker image prune -f 2>/dev/null || true
  
  # Remove unused networks
  docker network prune -f 2>/dev/null || true
  
  log_ok "Docker system cleaned"
}

# ── Summary ────────────────────────────────────
print_summary() {
  printf "\n${G}╔══════════════════════════════════════════════════════════════╗${N}\n"
  printf "${G}║${N}                                                              ${G}║${N}\n"
  printf "${G}║${N}          ${G}✅ RailDock has been uninstalled${N}                      ${G}║${N}\n"
  printf "${G}║${N}                                                              ${G}║${N}\n"
  printf "${G}╚══════════════════════════════════════════════════════════════╝${N}\n\n"

  if [ "$KEEP_DATA" = false ]; then
    printf "  ${Y}⚠️  Data has been deleted. This cannot be undone.${N}\n\n"
  fi

  printf "  To reinstall:\n"
  printf "    ${B}curl -sSL https://raw.githubusercontent.com/.../install.sh | bash${N}\n\n"
  
  if [ "$KEEP_DATA" = false ]; then
    printf "  To restore from backup (if you had one):\n"
    printf "    ${B}# Restore your data from backup first, then reinstall${N}\n\n"
  fi
}

# ── Main ───────────────────────────────────────
main() {
  print_banner
  
  check_docker
  
  # Check if anything is installed
  if ! is_stack_running && [ ! -d "$DATA_DIR" ] && [ ! -f "$ENV_FILE" ]; then
    log_info "RailDock doesn't appear to be installed"
    exit 0
  fi
  
  log_warn "This will uninstall RailDock and remove all associated data."
  echo ""
  
  if ! confirm "Are you sure you want to continue?" "n"; then
    log_info "Uninstall cancelled"
    exit 0
  fi
  
  stop_services
  remove_containers
  remove_images
  remove_volumes
  remove_networks
  remove_data_dir
  remove_ssh_keys
  remove_env_file
  clean_docker_system
  
  print_summary
}

main "$@"