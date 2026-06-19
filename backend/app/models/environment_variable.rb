class EnvironmentVariable < ApplicationRecord
  belongs_to :service

  validates :key, presence: true, uniqueness: { scope: :service_id }
  validates :key, format: { with: /\A[A-Za-z_][A-Za-z0-9_\-\.]*\z/, message: "must start with a letter or underscore and contain only letters, digits, underscores, dashes, or dots" }
  validates :value, presence: true
  validate :value_must_be_shell_safe

  before_save :sanitize_value

  private

  # Reject values that would break shell `source .env` parsing: embedded
  # newlines, carriage returns, NUL bytes, or unescaped `"` / `\` / `$` ` ` ` `.
  def value_must_be_shell_safe
    return if value.blank?
    return if value == value.to_s.gsub(/[\x00-\x1f\x7f]/, "")

    errors.add(:value, "must not contain control characters (newlines, tabs, etc.)")
  end

  # Strip trailing whitespace/CRLF that may have crept in via paste or copy.
  # Keeps interior content intact; only trims line-terminators and surrounding
  # whitespace, since Dokku stores env in shell-sourceable files.
  def sanitize_value
    self.value = value.to_s.gsub(/[\x00-\x08\x0b-\x1f\x7f]/, "").strip
  end
end
