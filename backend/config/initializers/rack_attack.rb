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
end

Rails.application.config.middleware.use Rack::Attack