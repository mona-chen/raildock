class EnvironmentVariable < ApplicationRecord
  belongs_to :service

  validates :key, presence: true, uniqueness: { scope: :service_id }
  validates :key, format: { with: /\A[A-Za-z_][A-Za-z0-9_\-\.]*\z/, message: "must start with a letter or underscore and contain only letters, digits, underscores, dashes, or dots" }
  validates :value, presence: true

  # Multi-line values are allowed: when written to Dokku we auto-encode
  # with --encoded (base64) so newlines survive the round-trip. We only
  # strip NUL bytes and trailing whitespace as sanitization.
  before_save :sanitize_value

  private

  def sanitize_value
    self.value = value.to_s.gsub(/\x00/, "").rstrip
  end
end
