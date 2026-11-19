require "digest"

# A machine credential that acts as a delegated user inside one organization.
#
# The secret is shown once at creation and only its SHA-256 digest is stored.
# `prefix` identifies the token in logs and in Settings without revealing it.
# Authorization is still the member's role; the token narrows it with `scopes`
# and an optional project/environment binding.
class ApiToken < ApplicationRecord
  PREFIX = "rd_".freeze
  PREFIX_LENGTH = 8
  TOUCH_INTERVAL = 1.minute
  SCOPES = %w[read deploy config:write destructive].freeze

  belongs_to :organization
  belongs_to :user
  belongs_to :project, optional: true
  belongs_to :environment, optional: true

  attr_accessor :plaintext

  before_validation :normalize_scopes
  before_validation :derive_project_from_environment

  validates :name, presence: true, length: { maximum: 80 }
  validate :scopes_are_known
  validate :environment_matches_project
  validate :binding_belongs_to_organization
  validate :expiry_is_in_the_future, on: :create

  scope :active, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  class << self
    def issue!(organization:, user:, name:, scopes:, project_id: nil, environment_id: nil, expires_at: nil)
      secret = "#{PREFIX}#{SecureRandom.urlsafe_base64(32)}"
      token = create!(
        organization: organization,
        user: user,
        name: name,
        scopes: scopes,
        project_id: project_id,
        environment_id: environment_id,
        expires_at: parse_expiry(expires_at),
        prefix: secret.delete_prefix(PREFIX).first(PREFIX_LENGTH),
        token_digest: digest(secret)
      )
      token.plaintext = secret
      token
    end

    # A string that the datetime type cannot cast would silently become `nil`,
    # turning an expiring token into an immortal one. Refuse it instead.
    def parse_expiry(value)
      return if value.blank?
      return value unless value.is_a?(String)

      Time.zone.parse(value) || raise(ArgumentError, "expires_at is not a valid time")
    rescue ArgumentError
      raise ArgumentError, "expires_at is not a valid time"
    end

    def digest(secret) = Digest::SHA256.hexdigest(secret.to_s)

    # Returns revoked and expired tokens too, so callers can explain which one
    # it is instead of reporting every failure as "unauthorized".
    def authenticate(secret)
      return if secret.blank? || !secret.start_with?(PREFIX)

      find_by(token_digest: digest(secret))
    end
  end

  def allows?(scope) = scopes.include?(scope.to_s)

  def revoked? = revoked_at.present?
  def expired? = expires_at.present? && expires_at <= Time.current
  def active? = !revoked? && !expired?

  def revoke!
    update!(revoked_at: Time.current)
  end

  # A write on every request would turn read-only polling into write load.
  def touch_last_used!
    return if last_used_at && last_used_at > TOUCH_INTERVAL.ago

    update_column(:last_used_at, Time.current)
  end

  private

  def normalize_scopes
    normalized = Array(scopes).map(&:to_s).uniq
    # A token that cannot read context cannot do anything useful, so every
    # write scope carries read with it.
    normalized |= [ "read" ] if normalized.any?
    self.scopes = normalized.sort_by { |scope| SCOPES.index(scope) || SCOPES.size }
  end

  def scopes_are_known
    if scopes.empty?
      errors.add(:scopes, "must include at least one scope")
    elsif (unknown = scopes - SCOPES).any?
      errors.add(:scopes, "contains unknown scopes: #{unknown.join(', ')}")
    end
  end

  def derive_project_from_environment
    self.project_id ||= environment.project_id if environment
  end

  def environment_matches_project
    return unless environment && project_id
    return if environment.project_id == project_id

    errors.add(:environment_id, "does not belong to the project")
  end

  def binding_belongs_to_organization
    if project && project.organization_id != organization_id
      errors.add(:project_id, "must belong to the organization")
    end
    if environment && environment.project.organization_id != organization_id
      errors.add(:environment_id, "must belong to the organization")
    end
  end

  def expiry_is_in_the_future
    return if expires_at.blank?

    errors.add(:expires_at, "must be in the future") if expires_at <= Time.current
  end
end
