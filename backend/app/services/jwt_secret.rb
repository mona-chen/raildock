# frozen_string_literal: true

# Single source of truth for the JWT signing key.
#
# `ENV.fetch` returns `""` when a variable is *set but blank*, and
# docker-compose passes `JWT_SECRET_KEY:` with no value on purpose in
# development. Callers therefore have to treat blank as absent, or the four
# places that sign and verify tokens silently disagree: one signs with `""`
# (JWT raises "HMAC key cannot be empty") while another falls back to
# `secret_key_base` and rejects every token the first one would have accepted.
module JwtSecret
  def self.value
    ENV["JWT_SECRET_KEY"].presence ||
      Rails.application.credentials.jwt_secret_key ||
      Rails.application.credentials.secret_key_base ||
      Rails.application.secret_key_base
  end
end
