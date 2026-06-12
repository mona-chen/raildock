# frozen_string_literal: true

# Default security headers for the Rails API and static frontend.
# These are applied by Rack::Protection::ContentSecurityPolicy and
# Rack::Protection::FrameOptions via Rails' default middleware.

Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.font_src    :self, :https, :data
  policy.img_src     :self, :https, :data
  policy.object_src  :none
  policy.script_src  :self, :https
  policy.style_src   :self, :https, :unsafe_inline
  policy.connect_src :self, :https
  policy.frame_ancestors :self
end

# Report violations without blocking in development/test.
if Rails.env.production?
  Rails.application.config.content_security_policy_report_only = ENV.fetch("CSP_REPORT_ONLY", "false") == "true"
else
  Rails.application.config.content_security_policy_report_only = true
end

Rails.application.config.action_dispatch.default_headers.merge!(
  "X-Frame-Options" => "SAMEORIGIN",
  "X-Content-Type-Options" => "nosniff",
  "Referrer-Policy" => "strict-origin-when-cross-origin",
  "Permissions-Policy" => "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()"
)
