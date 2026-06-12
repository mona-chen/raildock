class GitSource < ApplicationRecord
  belongs_to :organization, optional: true
  belongs_to :user, optional: true

  has_many :services, dependent: :nullify

  validates :provider, inclusion: { in: %w[github gitlab bitbucket gitea] }
  validate :must_belong_to_org_or_user
  validate :must_have_token_or_installation

  enum :auth_method, { oauth_app: 0, oauth2: 1, ssh_deploy_key: 2, token: 3 }
  enum :account_type, { personal: 0, organization: 1 }

  # OAuth fields (encrypted at rest)
  has_encrypted :access_token
  has_encrypted :refresh_token

  def owner
    organization || user
  end

  def repos
    metadata&.[]("repos") || []
  end

  def repos=(value)
    self.metadata ||= {}
    self.metadata["repos"] = value
  end

  def github_app?
    provider == "github" && installation_id.present?
  end

  def as_json(options = {})
    super(options.merge(except: [ :access_token_ciphertext, :refresh_token_ciphertext ]))
  end

  private

  def must_belong_to_org_or_user
    if organization_id.blank? && user_id.blank?
      errors.add(:base, "Must belong to an organization or a user")
    elsif organization_id.present? && user_id.present?
      errors.add(:base, "Cannot belong to both an organization and a user")
    end
  end

  def must_have_token_or_installation
    return unless connected?
    return if installation_id.present?
    return if access_token.present?

    errors.add(:base, "Must have an access token or installation ID")
  end
end
