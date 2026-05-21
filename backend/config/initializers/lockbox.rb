# Lockbox needs a 32-byte (64 hex char) key.
# Use RAILS_MASTER_KEY directly - don't access credentials here as it causes
# issues during Rails initialization when credentials.yml.enc is being loaded.
master_key = ENV.fetch('RAILS_MASTER_KEY') {
  # Generate a fallback only for development - should never happen in production
  SecureRandom.hex(32)
}
Lockbox.master_key = master_key[0, 64]