# Lockbox needs a 32-byte (256-bit) key for AES-256-GCM.
# RAILS_MASTER_KEY is 32 hex chars (16 bytes). We double it to get 32 bytes.
# Use RAILS_MASTER_KEY directly - don't access credentials here as it causes
# issues during Rails initialization when credentials.yml.enc is being loaded.

raw_key = ENV.fetch('RAILS_MASTER_KEY') {
  # Generate a fallback only for development - should never happen in production
  SecureRandom.hex(32)
}

# RAILS_MASTER_KEY is 32 hex chars. Lockbox needs 32 binary bytes.
# We'll use the key as-is but ensure it's binary-encoded.
# For hex keys, decode them. For raw keys, use them directly.
if raw_key.match?(/\A[a-fA-F0-9]+\z/) && raw_key.length == 64
  # 64 hex chars = 32 bytes binary
  Lockbox.master_key = [raw_key].pack('H*')
elsif raw_key.match?(/\A[a-fA-F0-9]+\z/) && raw_key.length == 32
  # 32 hex chars = 16 bytes. Double it for 32 bytes.
  Lockbox.master_key = [raw_key + raw_key].pack('H*')
elsif raw_key.length >= 32
  # Raw string - use first 32 bytes
  Lockbox.master_key = raw_key[0, 32].b
else
  # Short key - pad with random
  Lockbox.master_key = (raw_key + SecureRandom.hex(32 - raw_key.length))[0, 32].b
end