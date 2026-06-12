class Organization < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :memberships, class_name: "OrganizationMembership", dependent: :destroy
  has_many :users, through: :memberships
  has_many :projects, dependent: :destroy
  has_many :git_sources, dependent: :destroy
  has_many :deploy_keys, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  def members
    users.where(organization_memberships: { role: :member })
  end

  def admins
    users.where(organization_memberships: { role: [ :admin, :owner ] })
  end

  def member_count
    memberships.count
  end
end
