require "uri"

class MonitoringPolicy
  DEFAULTS = { "enabled" => false, "email" => false, "email_destinations" => [], "cpu" => 90, "memory" => 90, "disk" => 90, "http_error_percent" => 10, "requests_per_minute" => 1000, "suspicious_per_minute" => 0, "window_minutes" => 3, "retention_days" => 30 }.freeze
  RANGES = { "cpu" => 0..100, "memory" => 0..100, "disk" => 0..100, "http_error_percent" => 0..100, "requests_per_minute" => 0..1_000_000, "suspicious_per_minute" => 0..100_000, "window_minutes" => 1..15, "retention_days" => 1..90 }.freeze

  def self.for(organization)
    DEFAULTS.merge(organization&.notification_settings || {})
  end

  def self.validate!(values)
    raise ArgumentError, "Unknown notification setting" if (values.keys - DEFAULTS.keys).any?
    values.each do |key, value|
      if key == "email_destinations"
        valid = value.is_a?(Array) && value.length <= 10 && value.all? { |email| email.is_a?(String) && email.bytesize <= 254 && email.match?(URI::MailTo::EMAIL_REGEXP) && !email.match?(/\s/) }
        raise ArgumentError, "Enter up to 10 valid email addresses" unless valid
        next
      end
      valid = %w[enabled email].include?(key) ? [ true, false ].include?(value) : value.is_a?(Integer) && RANGES.fetch(key).cover?(value)
      raise ArgumentError, "Invalid #{key}" unless valid
    end
  end
end
