# Lockbox needs a 32-byte (64 hex char) key.
# Use a dedicated LOCKBOX_MASTER_KEY env var, fallback to derived from RAILS_MASTER_KEY.
master_key = ENV.fetch("LOCKBOX_MASTER_KEY") {
  ENV.fetch("RAILS_MASTER_KEY", nil) || "fallback-key-for-development-only"
}
Lockbox.master_key = master_key[0, 64]
