class Service < ApplicationRecord
  belongs_to :project
  has_many :environment_variables, dependent: :destroy
  has_many :domains, dependent: :destroy
  has_many :storage_mounts, dependent: :destroy
  has_many :deployments, dependent: :destroy
  has_many :process_types, dependent: :destroy
  has_many :backups, dependent: :destroy
  has_many :backup_schedules, dependent: :destroy

  has_many :outgoing_links, class_name: "ServiceLink", foreign_key: "from_service_id", dependent: :destroy
  has_many :incoming_links, class_name: "ServiceLink", foreign_key: "to_service_id", dependent: :destroy
  has_many :linked_services, through: :outgoing_links, source: :to_service
  has_many :linked_by_services, through: :incoming_links, source: :from_service

  validates :name, presence: true
  validates :service_type, inclusion: { in: %w[app database cache queue search service] }
  validates :status, inclusion: { in: %w[running stopped deploying error building] }

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

  enum :builder, {
    herokuish: "herokuish",
    pack: "pack",
    dockerfile: "dockerfile",
    nixpacks: "nixpacks",
    railpack: "railpack",
    lambda: "lambda",
    null_builder: "null"
  }

  enum :restart_policy, {
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
    DEFAULT_DOCKER_IMAGES[subtype]
  end

  scope :apps, -> { where(service_type: :app) }
  scope :databases, -> { where(service_type: :database) }
  scope :caches, -> { where(service_type: :cache) }

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
    detected_port || port || 5000
  end

  def as_json(options = {})
    super(options.merge(
      methods: [:type, :linked_service_ids, :linked_by_service_ids, :logs, :detected_port, :effective_port, :internal_hostname, :webhook_url],
      include: {
        environment_variables: { only: [:id, :key, :value, :source, :is_dokku_internal] },
        domains: { only: [:id, :hostname, :port, :target_port, :ssl, :letsencrypt, :temporary, :wildcard] },
        storage_mounts: { only: [:id, :host_path, :container_path] },
        process_types: { only: [:id, :name, :quantity, :running, :command] },
        backups: { only: [:id, :status, :size, :created_at] }
      }
    )).merge(
      "config" => config || {},
      "configOverrides" => config_overrides || {}
    )
  end

  private

  def generate_dokku_app_name
    self.dokku_app_name ||= "#{project.name.parameterize}-#{name.parameterize}"
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
end
