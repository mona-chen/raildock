# Lockbox needs a 32-byte (256-bit) key for AES-256-GCM.
# RAILS_MASTER_KEY is 32 hex chars (16 bytes). We double it to get 32 bytes.
# Use RAILS_MASTER_KEY directly - don't access credentials here as it causes
# issues during Rails initialization when credentials.yml.enc is being loaded.

raw_key = ENV["LOCKBOX_MASTER_KEY"].presence || ENV["RAILS_MASTER_KEY"].presence
if raw_key.blank?
  raise "LOCKBOX_MASTER_KEY or RAILS_MASTER_KEY must be set in production" if Rails.env.production?

  raw_key = SecureRandom.hex(32)
end

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
  raise "LOCKBOX_MASTER_KEY must be at least 32 bytes or 64 hex characters"
end
