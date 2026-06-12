class Rack::Attack
  # Throttle login attempts by IP
  throttle("logins/ip", limit: 5, period: 60.seconds) do |req|
    if req.path == "/api/login" && req.post?
      req.ip
    end
  end

  # Throttle login attempts by email (prevent email enumeration)
  throttle("logins/email", limit: 5, period: 60.seconds) do |req|
    if req.path == "/api/login" && req.post?
      email = req.params["email"].to_s.downcase
      email if email.include?("@")
    end
  end

  # Throttle registration endpoints
  throttle("registrations/ip", limit: 3, period: 60.seconds) do |req|
    if req.path == "/api/users" && req.post?
      req.ip
    end
  end

  # General API throttle — high limit for dashboard polling.
  # Excludes /api/me so auth checks never get blocked by polling bursts.
  throttle("api/all", limit: 600, period: 60.seconds) do |req|
    if req.path.start_with?("/api/") &&
       req.path != "/api/me" &&
       req.path != "/api/health" &&
       %w[GET POST PUT PATCH DELETE].include?(req.request_method)
      req.ip
    end
  end
end

# Return JSON for throttled responses so the frontend can handle gracefully
Rack::Attack.throttled_responder = lambda do |_env|
  [
    429,
    { "Content-Type" => "application/json", "Retry-After" => "60" },
    [ { error: "Rate limit exceeded. Please slow down.", retry_after: 60 }.to_json ]
  ]
end

Rails.application.config.middleware.use Rack::Attack
