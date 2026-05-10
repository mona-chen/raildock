#!/bin/sh
set -e

# Add authorized keys if provided
if [ -n "$AUTHORIZED_KEYS" ]; then
  echo "$AUTHORIZED_KEYS" > /home/dokku/.ssh/authorized_keys
  chmod 600 /home/dokku/.ssh/authorized_keys
  chown -R dokku:dokku /home/dokku/.ssh
fi

# Unlock dokku user so SSH key auth works
passwd -u dokku 2>/dev/null || true

# Ensure dokku user can run dokku without password
mkdir -p /etc/sudoers.d
echo "dokku ALL=(ALL) NOPASSWD: /usr/local/bin/dokku" > /etc/sudoers.d/dokku
chmod 440 /etc/sudoers.d/dokku

# Start sshd
exec /usr/sbin/sshd -D -e "$@"
