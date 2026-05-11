class User < ApplicationRecord
  has_secure_password

  has_many :organization_memberships, dependent: :destroy
  has_many :organizations, through: :organization_memberships
  has_many :owned_organizations, class_name: 'Organization', foreign_key: 'owner_id', dependent: :destroy

  # Personal git sources (not tied to an org)
  has_many :personal_git_sources, class_name: 'GitSource', foreign_key: 'user_id'
  has_many :deploy_keys, dependent: :destroy

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true

  def generate_jwt
    JWT.encode({ user_id: id, exp: 30.days.from_now.to_i }, Rails.application.credentials.secret_key_base)
  end
end
