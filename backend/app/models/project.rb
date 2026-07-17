class Project < ApplicationRecord
  belongs_to :organization, optional: true
  belongs_to :user, optional: true
  belongs_to :server, optional: true
  has_many :services, dependent: :destroy
  has_many :activity_events, dependent: :destroy

  before_destroy :destroy_services_dokku

  validates :name, presence: true
  validates :environment, inclusion: { in: %w[production staging development] }

  before_validation :set_default_environment, on: :create
  before_validation :set_default_server, on: :create
  after_create :set_network_name

  def set_network_name
    return if network_name.present?
    slug = name.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "").presence || "project"
    update_column(:network_name, "rd-#{slug}-#{id}")
  end

  def destroy_services_dokku
    return unless server&.ssh_key.present?
    engine = DokkuEngine.new(server)

    services.each do |service|
      if service.subtype_record&.has_capability?(:destroy)
        engine.datastore_destroy(service)
      else
        engine.app_destroy(service.dokku_app_name)
      end
    rescue StandardError
      # Log but don't block the destroy — DB record must be removed
      Rails.logger.error "Failed to destroy Dokku resource for service #{service.id}: #{$!.message}"
    end
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
