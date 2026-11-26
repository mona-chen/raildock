#!/usr/bin/env bash
set -euo pipefail
# Docker-compatible CLI override supports Kiri as well as Docker Desktop.
engine=${CONTAINER_CLI:-docker}
backend=${RAILDOCK_DEV_BACKEND:-raildock-backend-1}
organization=${LOCAL_DOKKU_ORG:-tween}
keyfile=$(mktemp)
trap 'rm -f "$keyfile"' EXIT
"$engine" exec -e LOCAL_DOKKU_ORG="$organization" "$backend" bin/rails runner \
  'puts Organization.find_by!(slug: ENV.fetch("LOCAL_DOKKU_ORG")).ensure_ssh_key!.public_key' > "$keyfile"
# The root key is needed for resource sampling; Dokku retains its forced command.
fingerprint=$(ssh-keygen -lf "$keyfile" | awk '{print $2}')
registered=$(limactl shell raildock-dokku sudo dokku ssh-keys:list)
if ! printf '%s\n' "$registered" | grep -F "$fingerprint " | grep -q 'NAME="raildock-local"'; then
  limactl shell raildock-dokku sudo dokku ssh-keys:add raildock-local < "$keyfile"
fi
limactl shell raildock-dokku sudo sh -c 'umask 077; mkdir -p /root/.ssh; key=$(cat); touch /root/.ssh/authorized_keys; grep -qxF "$key" /root/.ssh/authorized_keys || printf "%s\n" "$key" >> /root/.ssh/authorized_keys' < "$keyfile"
"$engine" exec -e LOCAL_DOKKU_ORG="$organization" "$backend" bin/rails runner db/seeds/real_dokku.rb
