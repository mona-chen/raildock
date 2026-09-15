class Project < ApplicationRecord
  belongs_to :organization, optional: true
  belongs_to :user, optional: true
  belongs_to :server, optional: true
  has_many :services, dependent: :destroy
  has_many :activity_events, dependent: :destroy

  # `prepend: true` matters: the dependent-association callbacks declared above
  # delete the service rows first, which would leave this guard looking at an
  # already-empty collection (and the Dokku resources orphaned/reachable only
  # through this hook).
  before_destroy :destroy_services_dokku, prepend: true

  validates :name, presence: true
  validates :environment, inclusion: { in: %w[production staging development] }

  before_validation :set_default_environment, on: :create
  before_validation :set_default_server, on: %i[create update]
  after_create :set_network_name

  # Opt-in flag for the before_destroy hook below. Deliberately not persisted.
  attr_accessor :allow_resource_destruction

  def set_network_name
    return if network_name.present?
    slug = name.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "").presence || "project"
    update_column(:network_name, "rd-#{slug}-#{id}")
  end

  # Destroying a Project row also destroys every Dokku app, datastore, and
  # volume it owns. That must never happen as a side effect of a bare
  # `project.destroy!`: callers have to opt in explicitly, after confirming the
  # intent and snapshotting any data. See Project#destroy_with_resources!.
  def destroy_services_dokku
    return if services.empty?
    return unless server&.ssh_key.present?

    unless allow_resource_destruction
      refuse_destruction!(
        "Refusing to destroy the Dokku resources of #{name.inspect} (services: #{services.pluck(:name).join(', ')}). " \
        "Set #allow_resource_destruction or use #destroy_with_resources! after confirming."
      )
    end

    engine = DokkuEngine.new(server)
    failures = []

    services.each do |service|
      result = if service.subtype_record&.has_capability?(:destroy)
        engine.datastore_destroy(service)
      else
        engine.app_destroy(service.dokku_app_name)
      end

      next if result.nil? || result[:success]

      failures << "#{service.name}: #{(result[:output] || result[:error]).to_s.strip}"
    end

    if failures.any?
      refuse_destruction!(
        "Dokku could not remove every resource for #{name.inspect}: #{failures.join('; ')}. " \
        "Nothing was deleted from RailDock so the failure can be retried safely."
      )
    end
  end

  # Records why the destroy was refused and aborts the callback chain.
  # `throw :abort` (not `raise`) keeps `destroy` returning false instead of
  # exploding out of callers such as Organization#destroy, while `destroy!`
  # still raises ActiveRecord::RecordNotDestroyed with these messages attached.
  def refuse_destruction!(message)
    errors.add(:base, message)
    throw :abort
  end

  # What destroying this project would take with it.
  def dokku_resource_summary
    {
      name: name,
      services: services.count,
      databases: services.where(service_type: "database").count,
      caches: services.where(service_type: "cache").count,
      storage_mounts: StorageMount.where(service_id: services.select(:id)).count,
      backups: Backup.where(service_id: services.select(:id)).count
    }
  end

  # Explicit destructive API used by the controller after the user typed the
  # project name to confirm.
  def destroy_with_resources!(confirmed: false)
    raise ArgumentError, "Project destruction must be confirmed" unless confirmed

    self.allow_resource_destruction = true
    destroy!
  rescue ActiveRecord::RecordNotDestroyed => e
    # `throw :abort` makes Rails raise a generic message; re-raise with the
    # reason the guard recorded so the API can explain what was kept and why.
    raise e if errors.empty?

    raise ActiveRecord::RecordNotDestroyed, errors.full_messages.join("; ")
  end

  # For backward compat + new org scoping
  scope :for_user, ->(user) {
    org_ids = user.organization_ids
    where(organization_id: org_ids).or(where(organization_id: nil, user_id: user.id))
  }

  scope :personal_for, ->(user) { where(organization_id: nil, user_id: user.id) }

  def set_default_environment
    self.environment ||= "production"
  end

  def set_default_server
    return if server_id.present?
    self.server ||= Server.where(user_id: user_id).first if user_id.present?
  end

  def service_ids
    services.pluck(:id)
  end

  def service_counts
    grouped = services.group(:service_type).count
    {
      total: services.count,
      app: grouped["app"] || 0,
      database: grouped["database"] || 0,
      cache: grouped["cache"] || 0
    }
  end

  def shared_vars
    read_attribute(:shared_vars) || []
  end

  # Serialized shape consumed by the UI. Always returns [{ key, value }, ...]
  # regardless of how the row was persisted (string "KEY=VALUE" entries or
  # already-parsed hashes), so the frontend never has to guess.
  def shared_vars_for_api
    shared_vars.map do |variable|
      if variable.is_a?(Hash)
        {
          key: variable["key"] || variable[:key],
          value: variable["value"] || variable[:value]
        }
      else
        key, value = variable.to_s.split("=", 2)
        { key: key, value: value }
      end
    end
  end

  def shared_var_map
    shared_vars.each_with_object({}) do |variable, result|
      if variable.is_a?(Hash)
        key = variable["key"] || variable[:key]
        value = variable["value"] || variable[:value]
      else
        key, value = variable.to_s.split("=", 2)
      end

      result[key] = value if key.present?
    end
  end

  def manifest_synced?
    # Drift means the stored manifest no longer describes what was applied, so
    # the project must not also be reported as "in sync".
    return false if manifest_drift_detected
    return false if manifest_last_applied_at.nil?

    manifest_last_synced_at.present? && manifest_last_applied_at >= manifest_last_synced_at
  end

  def has_deployments?
    Deployment.joins(:service).where(services: { project_id: id }).exists?
  end

  def as_json(options = {})
    super(options.merge(
      methods: [ :service_ids, :service_counts, :shared_vars_for_api, :manifest_synced?, :has_deployments? ]
    ))
  end
end
