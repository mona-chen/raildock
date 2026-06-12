# frozen_string_literal: true

# CORS is restricted to the configured FRONTEND_URL. Multiple origins can be
# supplied as a comma-separated list (e.g. "https://app.example.com,https://admin.example.com").
# Credentials are intentionally not allowed here; the frontend sends the JWT in
# the Authorization header. If cookie-based auth is introduced, set credentials: true
# and specify exact origins instead of wildcard methods.

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("FRONTEND_URL", "http://localhost:5173").split(",").map(&:strip)

    resource "/api/*",
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head]

    resource "/cable",
      headers: :any,
      methods: [:get, :post, :options]
  end
end
