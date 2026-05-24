class SystemSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  has_encrypted :encrypted_value

  SENSITIVE_KEYS = %w[
    github_app_pem
    github_client_secret
  ].freeze

  # GitHub App settings
  def self.github_app_slug = find_by(key: "github_app_slug")&.read_value
  def self.github_app_id = find_by(key: "github_app_id")&.read_value
  def self.github_client_id = find_by(key: "github_client_id")&.read_value
  def self.github_webhook_secret = find_by(key: "github_webhook_secret")&.read_value
  def self.github_app_pem = find_by(key: "github_app_pem")&.read_value
  def self.github_client_secret = find_by(key: "github_client_secret")&.read_value

  # Read value from either plain or encrypted field
  def read_value
    SENSITIVE_KEYS.include?(key) ? encrypted_value : value
  end

  # Write value to either plain or encrypted field
  def write_value(val)
    if SENSITIVE_KEYS.include?(key)
      self.encrypted_value = val
    else
      self.value = val
    end
  end

  # Upsert a setting
  def self.set!(key, val)
    record = find_or_initialize_by(key: key)
    record.write_value(val)
    record.save!
    record
  end
end
