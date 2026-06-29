class OrganizationInvitation < ApplicationRecord
  ROLES = %w[member admin].freeze
  EXPIRY = 7.days

  belongs_to :organization
  belongs_to :invited_by, class_name: "User"
  belongs_to :user, optional: true

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, inclusion: { in: ROLES }
  validates :token, presence: true, uniqueness: true
  validate :not_already_a_member, on: :create

  before_validation :generate_token, on: :create
  before_validation :set_expiry, on: :create

  scope :pending, -> { where(accepted_at: nil).where("expires_at > ?", Time.current) }
  scope :for_email, ->(email) { where("LOWER(email) = ?", email.to_s.downcase) }

  def accepted?
    accepted_at.present?
  end

  def expired?
    expires_at <= Time.current
  end

  def pending?
    !accepted? && !expired?
  end

  def as_json(options = {})
    super(options.reverse_merge(
      only: [ :id, :email, :role, :token, :expires_at, :accepted_at, :created_at ],
      include: { invited_by: { only: [ :id, :name, :email ] } }
    ))
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end

  def set_expiry
    self.expires_at ||= EXPIRY.from_now
  end

  def not_already_a_member
    return unless organization && email.present?
    return unless organization.users.where("LOWER(users.email) = ?", email.downcase).exists?

    errors.add(:email, "is already a member of this organization")
  end
end
