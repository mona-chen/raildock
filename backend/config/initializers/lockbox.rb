# Lockbox needs a 32-byte (64 hex char) key for AES-256-GCM.
# Generate a key from RAILS_MASTER_KEY or use a random one.
# Use RAILS_MASTER_KEY directly - don't access credentials here as it causes
# issues during Rails initialization when credentials.yml.enc is being loaded.
raw_key = ENV.fetch('RAILS_MASTER_KEY') {
  # Generate a fallback only for development - should never happen in production
  SecureRandom.hex(32)
}

# Lockbox expects the key to be binary (32 bytes) for AES-256-GCM
# If the raw_key is hex, decode it. Otherwise, use first 32 bytes.
if raw_key.match?(/\A[a-fA-F0-9]+\z/) && raw_key.length == 64
  # Hex-encoded key - decode to binary
  Lockbox.master_key = [raw_key].pack('H*')
elsif raw_key.length >= 32
  # Raw key - take first 32 bytes
  Lockbox.master_key = raw_key[0, 32]
else
  # Short key - pad with random
  Lockbox.master_key = raw_key.ljust(32, SecureRandom.hex(16))[0, 32]
end