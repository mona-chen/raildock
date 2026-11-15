# frozen_string_literal: true

# Instance-wide collection policy; disabling collection keeps retained history.
class ObservabilitySettings
  DEFAULTS = {
    "metrics_services_enabled" => "true",
    "metrics_hosts_enabled" => "true",
    "metrics_retention_days" => "30"
  }.freeze

  def self.values
    DEFAULTS.merge(SystemSetting.where(key: DEFAULTS.keys).to_h { |setting| [ setting.key, setting.read_value ] })
  end

  def self.services_enabled? = values["metrics_services_enabled"] == "true"
  def self.hosts_enabled? = values["metrics_hosts_enabled"] == "true"
  def self.retention_days = values["metrics_retention_days"].to_i.clamp(1, 90)

  def self.validate!(settings)
    settings.each do |key, value|
      next unless DEFAULTS.key?(key)
      valid = if key == "metrics_retention_days"
        value.to_s.match?(/\A\d+\z/) && (1..90).cover?(value.to_i)
      else
        %w[true false].include?(value.to_s)
      end
      raise ArgumentError, "Invalid #{key}" unless valid
    end
  end
end
