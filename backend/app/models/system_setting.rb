class SystemSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  # GitHub App settings
  def self.github_app_slug = find_by(key: "github_app_slug")&.value
  def self.github_app_id = find_by(key: "github_app_id")&.value
  def self.github_client_id = find_by(key: "github_client_id")&.value
  def self.github_webhook_secret = find_by(key: "github_webhook_secret")&.value

  # Upsert a setting
  def self.set!(key, value)
    record = find_or_initialize_by(key: key)
    record.update!(value: value)
    record
  end
end
