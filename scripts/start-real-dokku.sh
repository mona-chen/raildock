#!/usr/bin/env bash
# Dedicated Linux host: never installs Dokku into the developer's shared engine.
set -euo pipefail
command -v limactl >/dev/null || { echo 'Install Lima first: brew install lima'; exit 1; }
instance=raildock-dokku
if ! limactl list --json | python3 -c 'import json,sys; sys.exit(not any(json.loads(l)["name"] == "raildock-dokku" for l in sys.stdin if l.strip()))'; then
  limactl start --name="$instance" --vm-type=vz --cpus=2 --memory=3 --disk=20 \
    --mount-none --containerd=none --ssh-port=52222 --port-forward=5280:80 \
    --tty=false template:ubuntu-24.04
else
  limactl start --tty=false "$instance"
fi
# Pin the supported engine version; repeat runs do not upgrade existing hosts.
limactl shell "$instance" sudo bash -s <<'GUEST'
set -euo pipefail
if ! command -v dokku >/dev/null; then
  apt-get update
  apt-get install -y curl ca-certificates python3
  curl --fail --silent --show-error --location https://raw.githubusercontent.com/dokku/dokku/v0.38.34/bootstrap.sh -o /tmp/raildock-dokku-bootstrap.sh
  DOKKU_TAG=v0.38.34 bash /tmp/raildock-dokku-bootstrap.sh
fi
dokku version
GUEST
printf '\nReal Dokku is running in %s. SSH: localhost:52222; HTTP: localhost:5280\n' "$instance"
printf 'Use limactl shell %s for the Linux console. Stop with: limactl stop %s\n' "$instance" "$instance"
