class Organization < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :memberships, class_name: "OrganizationMembership", dependent: :destroy
  has_many :users, through: :memberships
  has_many :invitations, class_name: "OrganizationInvitation", dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :git_sources, dependent: :destroy
  has_many :deploy_keys, dependent: :destroy
  # See Server: backup destinations hold off-host artifacts and must be removed
  # deliberately, never as a cascade side effect.
  has_many :backup_destinations, dependent: :restrict_with_error
  has_one :ssh_key, class_name: "OrganizationSshKey", dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  # Backup destinations new backups inherit when a service has not picked its
  # own. Stored as ids rather than an association because the list is a default,
  # not ownership: a destination deleted later must not be resurrected by this
  # column, so it is pruned on delete instead (see `BackupDestination`).
  validate :default_backup_destinations_are_owned

  def default_backup_destination_ids=(ids)
    super(Array(ids).map(&:to_s).compact_blank.uniq)
  end

  def members
    users.where(organization_memberships: { role: :member })
  end

  def admins
    users.where(organization_memberships: { role: [ :admin, :owner ] })
  end

  def member_count
    memberships.count
  end

  def pending_invitations
    invitations.pending.order(created_at: :desc)
  end

  def owner_membership
    memberships.find_by(role: :owner)
  end

  def ensure_ssh_key!
    ssh_key || OrganizationSshKeyService.generate(self)
  end

  private
    def default_backup_destinations_are_owned
      return if default_backup_destination_ids.blank?

      unknown = Array(default_backup_destination_ids).map(&:to_s) - backup_destinations.ids.map(&:to_s)
      errors.add(:default_backup_destination_ids, "reference unknown destinations: #{unknown.join(', ')}") if unknown.any?
    end
end
