# Lockbox needs a 32-byte (64 hex char) key.
# Derive it from the first 64 hex chars of Rails secret_key_base.
Lockbox.master_key = Rails.application.credentials.secret_key_base[0, 64]
