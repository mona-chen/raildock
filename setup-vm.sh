#!/bin/sh
# RailDock VM Setup Script
# Run this inside the Macpine VM

set -e

echo "=== RailDock VM Setup ==="

# Enable community repo for Docker
sed -i 's/#http/http/g' /etc/apk/repositories
apk update

# Install Docker
echo "Installing Docker..."
apk add docker docker-cli docker-cli-compose
service docker start
rc-update add docker boot

# Wait for Docker
sleep 3
docker info >/dev/null 2>&1 || {
  echo "Docker failed to start"
  exit 1
}

echo "Docker ready"

# Go to project
cd /mnt/raildock

# Generate secrets
echo "Generating secrets..."
export RAILDOCK_DOMAIN=
export RAILDOCK_EMAIL=admin@localhost
export POSTGRES_PASSWORD=$(openssl rand -hex 32)
export RAILS_MASTER_KEY=$(openssl rand -hex 16)
export ADMIN_PASSWORD=changeme123

# Write .env
cat > .env <<EOF
RAILDOCK_DOMAIN=${RAILDOCK_DOMAIN}
RAILDOCK_EMAIL=${RAILDOCK_EMAIL}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
RAILS_MASTER_KEY=${RAILS_MASTER_KEY}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
EOF
chmod 600 .env

# Build and start
echo "Building Docker images... (this takes 5-10 minutes)"
docker compose pull
docker compose up -d --build

# Wait for backend health
echo "Waiting for backend..."
for i in $(seq 1 60); do
  if docker compose exec -T backend curl -sf http://localhost:3000/api/health >/dev/null 2>&1; then
    echo ""
    echo "Backend is healthy!"
    break
  fi
  echo -n "."
  sleep 2
done

# Create admin
echo ""
echo "Creating admin user..."
docker compose exec -T backend bin/rails runner "
  exit(User.exists? ? 1 : 0)
" >/dev/null 2>&1 && echo "Admin already exists" || docker compose exec -T backend bin/rails runner "
  User.create!(name: 'Admin', email: 'admin@raildock.local', password: '${ADMIN_PASSWORD}')
  puts 'Admin created'
"

# Done
echo ""
echo "========================================"
echo "RailDock is running!"
echo "========================================"
echo ""
docker compose ps
echo ""
echo "Login: admin@raildock.local"
echo "Pass:  ${ADMIN_PASSWORD}"
echo ""
echo "From your Mac, run:"
echo "  ssh -L 8080:localhost:80 -N -p 2222 root@localhost"
echo "Then open http://localhost:8080"
echo ""
