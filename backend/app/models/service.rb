class Service < ApplicationRecord
  belongs_to :project
  has_many :environment_variables, dependent: :destroy
  has_many :domains, dependent: :destroy
  has_many :storage_mounts, dependent: :destroy
  has_many :deployments, dependent: :destroy
  has_many :process_types, dependent: :destroy
  has_many :backups, dependent: :destroy
  has_many :backup_schedules, dependent: :destroy
  has_many :service_metrics, dependent: :destroy
  has_one :postgres_pitr_config, dependent: :destroy

  has_many :outgoing_links, class_name: "ServiceLink", foreign_key: "from_service_id", dependent: :destroy
  has_many :incoming_links, class_name: "ServiceLink", foreign_key: "to_service_id", dependent: :destroy
  has_many :linked_services, through: :outgoing_links, source: :to_service
  has_many :linked_by_services, through: :incoming_links, source: :from_service

  # Registry-backed subtype. The string value in `subtype` remains the source
  # of truth; the association is a convenience for joins/preloading.
  belongs_to :service_subtype, optional: true, foreign_key: "subtype", primary_key: "subtype", inverse_of: :services
  has_one :plugin, through: :service_subtype

  validates :name, presence: true
  validates :service_type, inclusion: { in: %w[app database cache queue search service] }
  validates :status, inclusion: { in: %w[running stopped deploying error building] }
  validate :subtype_must_be_registered, on: :create
  validate :builder_must_be_registered, on: :create, if: -> { service_type_app? }

  enum :service_type, {
    app: "app",
    database: "database",
    cache: "cache",
    queue: "queue",
    search: "search",
    service: "service"
  }, prefix: true

  enum :status, {
    running: "running",
    stopped: "stopped",
    deploying: "deploying",
    error: "error",
    building: "building"
  }

  enum :restart_policy, {
    never: "never",
    on_failure: "on-failure",
    always: "always",
    unless_stopped: "unless-stopped"
  }

  enum :managed_by, {
    ui: "ui",
    manifest: "manifest",
    hybrid: "hybrid"
  }, prefix: true, default: :ui

  # Default Docker images for one-click service subtypes that don't have a git repo
  DEFAULT_DOCKER_IMAGES = {
    "minio" => "minio/minio:latest",
    "rabbitmq" => "rabbitmq:alpine",
    "elasticsearch" => "elasticsearch:8",
    "meilisearch" => "getmeili/meilisearch:latest",
    "typesense" => "typesense/typesense:latest"
  }.freeze

  before_create :generate_dokku_app_name
  before_create :generate_webhook_token

  def default_docker_image
    subtype_record&.default_image || DEFAULT_DOCKER_IMAGES[subtype]
  end

  def subtype_record
    return @subtype_record if defined?(@subtype_record)

    @subtype_record = subtype.present? ? PluginRegistry.find_subtype(subtype) : nil
  end

  def builder_record
    return @builder_record if defined?(@builder_record)

    @builder_record = builder.present? ? PluginRegistry.find_builder(builder) : nil
  end

  scope :apps, -> { where(service_type: :app) }
  scope :databases, -> { where(service_type: :database) }
  scope :caches, -> { where(service_type: :cache) }

  def self.matching_repo(*identifiers)
    normalized = identifiers.flatten.compact_blank.flat_map { |value| repo_identifiers(value) }.uniq
    return none if normalized.empty?

    where(git_repo: normalized)
  end

  def self.repo_identifiers(value)
    raw = value.to_s.strip
    return [] if raw.blank?

    normalized = raw.delete_suffix(".git")
    full_name = repo_full_name(normalized)
    identifiers = [ raw, normalized ]

    if full_name.present?
      identifiers.concat([
        full_name,
        "https://github.com/#{full_name}.git",
        "https://github.com/#{full_name}",
        "git@github.com:#{full_name}.git",
        "ssh://git@github.com/#{full_name}.git"
      ])
    end

    identifiers.uniq
  end

  def self.repo_full_name(value)
    raw = value.to_s.strip
    return nil if raw.blank?

    if raw.match?(/\A[\w.-]+\/[\w.-]+(?:\.git)?\z/)
      return raw.delete_suffix(".git")
    end

    if (match = raw.match(/\Agit@github\.com:(?<full>[^\/\s]+\/[^\/\s]+?)(?:\.git)?\z/i))
      return match[:full].delete_suffix(".git")
    end

    uri = URI.parse(raw)
    return nil unless uri.host&.casecmp("github.com")&.zero?

    uri.path.to_s.sub(%r{\A/}, "").delete_suffix(".git").presence
  rescue URI::InvalidURIError
    nil
  end

  # Dokku app names must start with a lowercase alphanumeric character and
  # cannot contain uppercase letters, colons, or underscores. Rails parameterize
  # preserves underscores, so we normalize them to hyphens here.
  def self.dokku_app_name_for(project_name, service_name, suffix: nil)
    base = "#{project_name.to_s.parameterize}-#{service_name.to_s.parameterize}"
    base = "#{base}-#{suffix}" if suffix.present?
    base.gsub("_", "-").gsub(/-+/, "-").gsub(/^-|-$/, "").downcase
  end

  def type
    service_type
  end

  def linked_service_ids
    linked_services.pluck(:id)
  end

  def linked_by_service_ids
    linked_by_services.pluck(:id)
  end

  def docker_image_database?
    return true if service_type_database?
    return false if docker_image.blank?

    img = docker_image.downcase
    img.include?("postgres") || img.include?("mysql") || img.include?("mariadb") ||
      img.include?("redis") || img.include?("mongo") || img.include?("postgres") ||
      img.include?("clickhouse") || img.include?("qdrant") || img.include?("meilisearch") ||
      img.include?("typesense") || img.include?("elasticsearch") || img.include?("minio")
  end

  def logs
    # Return recent deployments' logs as log entries
    deployments.order(created_at: :desc).limit(10).flat_map do |d|
      [
        { timestamp: d.started_at, process_type: "deploy", message: "Deployment #{d.status}" }
      ]
    end
  end

  def effective_port
    port || detected_port || 5000
  end

  # Whether the built-in database viewer supports this service.
  def data_view
    subtype_record&.has_capability?(:query) || false
  end

  def as_json(options = {})
    super(options.merge(
      methods: [ :type, :linked_service_ids, :linked_by_service_ids, :logs, :detected_port, :effective_port, :internal_hostname, :webhook_url, :data_view ],
      include: {
        environment_variables: { only: [ :id, :key, :value, :source, :is_dokku_internal ] },
        domains: { only: [ :id, :hostname, :port, :target_port, :ssl, :letsencrypt, :temporary, :wildcard ] },
        storage_mounts: { only: [ :id, :host_path, :container_path, :kind ] },
        process_types: { only: [ :id, :name, :quantity, :running, :command ] },
        backups: { only: [ :id, :status, :size, :created_at ] }
      }
    )).merge(
      "config" => config || {},
      "configOverrides" => config_overrides || {}
    )
  end

  private

  def generate_dokku_app_name
    self.dokku_app_name ||= Service.dokku_app_name_for(project.name, name, suffix: SecureRandom.hex(4))
  end

  def generate_webhook_token
    self.webhook_token ||= SecureRandom.hex(32)
  end

  def webhook_url
    return nil if webhook_token.blank?
    base = ENV.fetch("RAILDOCK_API_URL", "")
    return nil if base.blank?
    "#{base.chomp("/")}/api/services/#{id}/webhooks/#{webhook_token}/deploy"
  end

  def subtype_must_be_registered
    return if subtype.blank?
    return if PluginRegistry.has_capability?(subtype, :create) ||
              PluginRegistry.has_capability?(subtype, :docker_deploy) ||
              PluginRegistry.has_capability?(subtype, :deploy)

    errors.add(:subtype, "'#{subtype}' is not a registered service subtype")
  end

  def builder_must_be_registered
    return if builder.blank?
    return if PluginRegistry.find_builder(builder).present?

    errors.add(:builder, "'#{builder}' is not a registered builder")
  end
end
