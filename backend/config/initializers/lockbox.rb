# Lockbox needs a 32-byte (64 hex char) key.
# Use a dedicated LOCKBOX_MASTER_KEY env var, fallback to derived from RAILS_MASTER_KEY for migration.
Lockbox.master_key = ENV.fetch("LOCKBOX_MASTER_KEY") { Rails.application.credentials.secret_key_base[0, 64] }
