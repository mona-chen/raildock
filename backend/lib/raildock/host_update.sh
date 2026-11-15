#!/usr/bin/env bash
# Runs on the installation host under a transient systemd service, never in RailDock.
set -euo pipefail
install_dir=$1
version=$2
operation=$3
[[ "$version" =~ ^(edge|[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?)$ ]] || exit 2
[[ "$operation" =~ ^[a-f0-9]{32}$ ]] || exit 2
cd "$install_dir"
[[ -f docker-compose.yml && -f .env ]] || exit 2
state_dir="$install_dir/data/updates/$operation"
umask 077
mkdir -p "$state_dir"
exec >>"$state_dir/output.log" 2>&1
exec 9>"$install_dir/data/updates/update.lock"
status() {
  printf '{"id":"%s","status":"%s","version":"%s"}\n' "$operation" "$1" "$version" > "$state_dir/status.tmp"
  mv "$state_dir/status.tmp" "$state_dir/status.json"
}
flock -n 9 || { status busy; exit 1; }
status scheduled
# Let the API acknowledge scheduling before its container can be replaced.
sleep 5
export RAILDOCK_VERSION="$version"
compose=(docker compose -f "$install_dir/docker-compose.yml")
old_container=$("${compose[@]}" ps -q raildock)
[[ -n "$old_container" ]] || { status failed; exit 1; }
old_image=$(docker inspect --format '{{.Image}}' "$old_container")
old_version=$(docker image inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$old_image" | sed -n 's/^RAILDOCK_VERSION=//p')
[[ "$old_version" =~ ^[A-Za-z0-9.-]+$ ]] || old_version=unknown
[[ "$old_image" =~ ^sha256:[a-f0-9]{64}$ ]] || { status failed; exit 1; }
replacing=0
healthy() {
  local container health
  for ((attempt=0; attempt<90; attempt++)); do
    container=$("${compose[@]}" ps -q raildock)
    health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container" 2>/dev/null || true)
    [[ "$health" == healthy ]] && return 0
    [[ "$health" == unhealthy || "$health" == missing ]] && return 1
    sleep 2
  done
  return 1
}
finish() {
  code=$?
  trap - EXIT
  if ((code != 0)); then
    if ((replacing)); then
      status rolling_back
      printf 'services:\n  raildock:\n    image: "%s"\n    environment:\n      RAILDOCK_VERSION: "%s"\n' "$old_image" "$old_version" > "$state_dir/rollback.yml"
      if "${compose[@]}" -f "$state_dir/rollback.yml" up -d --no-deps --pull never raildock && healthy; then
        status rolled_back
      else
        status failed
      fi
    else
      status failed
    fi
  fi
  exit "$code"
}
trap finish EXIT
status pulling
timeout 600 "${compose[@]}" pull raildock
status backing_up
# DATABASE_URL is expanded inside the old container, never in the host shell.
# shellcheck disable=SC2016
timeout 600 docker exec "$old_container" sh -c 'pg_dump --format=custom "$DATABASE_URL"' > "$state_dir/database.dump"
[[ -s "$state_dir/database.dump" ]]
docker exec -i "$old_container" pg_restore --list < "$state_dir/database.dump" > "$state_dir/backup-catalog.txt"
sha256sum "$state_dir/database.dump" > "$state_dir/database.dump.sha256"
sha256sum -c "$state_dir/database.dump.sha256"
cp .env "$state_dir/env.backup"
status restarting
replacing=1
"${compose[@]}" up -d --no-deps raildock
status verifying
healthy
# Persist the selected image only after its health check succeeds.
if grep -q '^RAILDOCK_VERSION=' .env; then
  sed "s/^RAILDOCK_VERSION=.*/RAILDOCK_VERSION=$version/" .env > "$state_dir/env.next"
else
  cat .env > "$state_dir/env.next"
  printf '\nRAILDOCK_VERSION=%s\n' "$version" >> "$state_dir/env.next"
fi
cat "$state_dir/env.next" > .env
status completed
