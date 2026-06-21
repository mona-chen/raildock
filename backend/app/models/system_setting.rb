class SystemSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  has_encrypted :encrypted_value

  SENSITIVE_KEYS = %w[
    github_app_pem
    github_client_secret
    smtp_password
  ].freeze

  GITHUB_APP_KEYS = %w[
    github_app_slug
    github_app_id
    github_client_id
    github_webhook_secret
    github_app_pem
    github_client_secret
  ].freeze

  SMTP_KEYS = %w[
    smtp_enabled
    smtp_address
    smtp_port
    smtp_username
    smtp_password
    smtp_domain
    smtp_auth
    smtp_starttls
  ].freeze

  # GitHub App settings
  def self.github_app_slug = find_by(key: "github_app_slug")&.read_value
  def self.github_app_id = find_by(key: "github_app_id")&.read_value
  def self.github_client_id = find_by(key: "github_client_id")&.read_value
  def self.github_webhook_secret = find_by(key: "github_webhook_secret")&.read_value
  def self.github_app_pem = find_by(key: "github_app_pem")&.read_value
  def self.github_client_secret = find_by(key: "github_client_secret")&.read_value

  # SMTP settings
  def self.smtp_enabled = find_by(key: "smtp_enabled")&.read_value == "true"
  def self.smtp_address = find_by(key: "smtp_address")&.read_value
  def self.smtp_port = find_by(key: "smtp_port")&.read_value&.to_i
  def self.smtp_username = find_by(key: "smtp_username")&.read_value
  def self.smtp_password = find_by(key: "smtp_password")&.read_value
  def self.smtp_domain = find_by(key: "smtp_domain")&.read_value
  def self.smtp_auth = find_by(key: "smtp_auth")&.read_value&.to_sym
  def self.smtp_starttls = find_by(key: "smtp_starttls")&.read_value

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
