#!/bin/bash
# Fix credentials.yml.enc for fresh install

set -e

cd /opt/raildock
source .env

echo "=== Current credentials.yml.enc ==="
cat backend/config/credentials.yml.enc
echo ""

echo "=== RAILS_MASTER_KEY ==="
echo "$RAILS_MASTER_KEY"

# Check if credentials can be decrypted
docker compose run --rm -e RAILS_MASTER_KEY="$RAILS_MASTER_KEY" backend \
  bash -c "bundle exec rails credentials:show --skip-irods >/dev/null 2>&1 && echo DECRYPT_OK || echo DECRYPT_FAIL"

# If decryption fails, regenerate credentials
if docker compose run --rm -e RAILS_MASTER_KEY="$RAILS_MASTER_KEY" backend \
  bash -c "bundle exec rails credentials:show --skip-irods" 2>/dev/null | grep -q "DECRYPT_OK"; then
  echo "Credentials can be decrypted!"
else
  echo "Cannot decrypt credentials, regenerating..."
  
  # Create new credentials.yml.enc
  docker compose run --rm -e RAILS_MASTER_KEY="$RAILS_MASTER_KEY" backend \
    bash -c "bundle exec rails credentials:edit --skip-irods <<EOF
# Used as the base secret for all MessageVerifiers in Rails, including the one protecting cookies.
secret_key_base: $RAILS_MASTER_KEY
EOF
" 2>/dev/null || echo "Interactive edit failed"
  
  echo "=== New credentials.yml.enc ==="
  cat backend/config/credentials.yml.enc
fi