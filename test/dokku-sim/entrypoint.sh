#!/bin/sh
set -e

# RailDock's control-plane key comes from AUTHORIZED_KEYS when the image is run
# standalone (integration tests), or from the mounted key pair otherwise.
KEYS="${AUTHORIZED_KEYS:-}"
if [ -z "$KEYS" ] && [ -f /keys/id_ed25519.pub ]; then
  KEYS="$(cat /keys/id_ed25519.pub)"
fi

# A real Dokku host authorizes the control-plane key for both the `dokku` user
# (app and datastore commands) and `root` (host metrics, provisioning). The
# simulator has to do the same, otherwise whole surfaces of the UI would look
# broken for no good reason.
if [ -n "$KEYS" ]; then
  for ssh_home in /home/dokku /root; do
    mkdir -p "$ssh_home/.ssh"
    echo "$KEYS" > "$ssh_home/.ssh/authorized_keys"
    chmod 700 "$ssh_home/.ssh"
    chmod 600 "$ssh_home/.ssh/authorized_keys"
  done
  # The `dokku` user is restricted to the shim, exactly like a real Dokku host.
  # Without this, RailDock's bare subcommands ("domains:add app host") would run
  # in a plain login shell and fail, silently disabling every Dokku call.
  echo 'command="/usr/local/bin/dokku" '"$(cat /home/dokku/.ssh/authorized_keys)" > /home/dokku/.ssh/authorized_keys
  chown -R dokku:dokku /home/dokku/.ssh
fi

# Unlock dokku user so SSH key auth works
passwd -u dokku 2>/dev/null || true

# Root logs in by key only, never by password.
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

# Ensure dokku user can run dokku without password
mkdir -p /etc/sudoers.d
echo "dokku ALL=(ALL) NOPASSWD: /usr/local/bin/dokku" > /etc/sudoers.d/dokku
chmod 440 /etc/sudoers.d/dokku

# Start sshd
exec /usr/sbin/sshd -D -e "$@"
