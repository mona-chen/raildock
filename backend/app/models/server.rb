class Server < ApplicationRecord
  # Deleting a server must not silently detach the projects deployed on it:
  # their apps keep running on the host with nothing in RailDock pointing at
  # them. The controller refuses with `server_has_projects`; this is the
  # backstop for any other caller.
  has_many :projects, dependent: :restrict_with_error
  has_many :server_metrics, dependent: :delete_all
  has_many :http_traffic_buckets, dependent: :delete_all
  has_many :monitoring_incidents, dependent: :delete_all
  # `restrict_with_error`, not `destroy`: a destination owns off-host artifacts
  # that outlive both the server and RailDock itself. Destroying it as a side
  # effect of deleting a server would delete rows that reference those objects,
  # and `dependent: :destroy` silently ignores a refused child destroy (the FK
  # then blows up mid-transaction).
  has_many :backup_destinations, dependent: :restrict_with_error
  belongs_to :user, optional: true
  belongs_to :organization, optional: true

  validates :name, presence: true
  validates :host, presence: true
  validates :host, uniqueness: { scope: :organization_id, case_sensitive: false }, if: :organization_id?
  validates :host, uniqueness: { scope: :user_id, case_sensitive: false }, if: -> { organization_id.blank? && user_id.present? }
  validate :ssh_key_format, if: -> { ssh_key.present? }
  DEFAULT_SSH_PORT = 22
  validates :ssh_port, numericality: { only_integer: true, greater_than: 0, less_than: 65_536 }

  enum :status, {
    connected: "connected",
    disconnected: "disconnected",
    error: "error"
  }, default: "disconnected"

  PROXY_TYPES = %w[nginx traefik caddy haproxy openresty].freeze
  PROXY_MODES = %w[managed external].freeze

  validates :proxy_mode, inclusion: { in: PROXY_MODES }
  validates :external_proxy_network, presence: true, if: :external_proxy?

  SETUP_OWNER_TTL = 2.hours
  SETUP_ID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  # A provisioning setup id is a bearer handle for the setup log stream (which
  # carries host details), so remember who started it and only let members of
  # that organization read it.
  def self.record_setup_owner!(setup_id, organization_id:, user_id:)
    Rails.cache.write(setup_owner_key(setup_id), { organization_id: organization_id, user_id: user_id }, expires_in: SETUP_OWNER_TTL)
  end

  def self.setup_owner(setup_id)
    return nil unless setup_id.to_s.match?(SETUP_ID_FORMAT)

    Rails.cache.read(setup_owner_key(setup_id))
  end

  def self.setup_accessible_by?(setup_id, user, organization: nil)
    owner = setup_owner(setup_id)
    return false unless owner && user
    return false if organization && organization.id.to_s != owner[:organization_id].to_s

    owner[:user_id].to_s == user.id.to_s ||
      user.organization_memberships.exists?(organization_id: owner[:organization_id])
  end

  # Default server for a new project: a connected one first (ServerHealthCheckJob
  # keeps `status` fresh), then the oldest, so the choice is stable.
  def self.preferred_for_new_project(scope)
    scope.order(Arel.sql("CASE servers.status WHEN 'connected' THEN 0 WHEN 'disconnected' THEN 1 ELSE 2 END"))
      .order(:id)
      .first
  end

  def self.setup_owner_key(setup_id)
    "server_setup_owner:#{setup_id}"
  end

  # Shared Lockbox instance for encryption/decryption (class-level for efficiency)
  LOCKBOX = Lockbox.new(key: Lockbox.master_key, encode: true)

  def ssh_key
    ciphertext = self[:ssh_key_ciphertext]
    return nil if ciphertext.blank?

    self.class::LOCKBOX.decrypt(ciphertext)
  rescue Lockbox::DecryptionError => e
    Rails.logger.error "Failed to decrypt SSH key for server #{id}: #{e.message}"
    nil
  end

  def ssh_key=(value)
    if value.present?
      self[:ssh_key_ciphertext] = self.class::LOCKBOX.encrypt(value)
    else
      self[:ssh_key_ciphertext] = nil
    end
  end

  def ssh_user
    self[:ssh_user].presence || DokkuEngineConstants::SSH_USER
  end

  # Every SSH client goes through SshConnectionBuilder, which reads this, so a
  # host with sshd on a non-standard port works for deploys, metrics and logs.
  def ssh_port
    self[:ssh_port].presence || DEFAULT_SSH_PORT
  end

  def default_proxy
    self[:default_proxy].presence || "traefik"
  end

  def external_proxy?
    proxy_mode == "external"
  end

  def disk_usage
    { used: disk_used || 0, total: disk_total || 0 }
  end

  def memory_usage
    { used: memory_used || 0, total: memory_total || 0 }
  end

  def project_ids
    projects.pluck(:id)
  end

  def auto_domains?
    base_domain.present?
  end

  def base_domain
    self[:base_domain].presence || "sslip.io"
  end

  # Magic DNS services that resolve wildcards to embedded IPs
  MAGIC_DOMAINS = %w[sslip.io nip.io traefik.me].freeze

  def magic_domain?
    MAGIC_DOMAINS.include?(base_domain&.downcase)
  end

  # Build a temporary hostname for a given app name.
  # For magic domains, embeds the server's public IP so it resolves correctly.
  def temporary_hostname(app_name)
    return nil unless base_domain.present?

    if magic_domain?
      ip = public_ip || host
      # sslip.io supports both dot and dash notation; dots are more natural
      "#{app_name}.#{ip}.#{base_domain}"
    else
      "#{app_name}.#{base_domain}"
    end
  end

  def as_json(options = {})
    super(options.merge(
      methods: [ :disk_usage, :memory_usage, :project_ids, :default_proxy, :ssh_user, :base_domain, :auto_domains, :resource_summary ],
      except: [ :ssh_key_ciphertext, :host_key, :traffic_cursor ]
    ))
  end

  # Overview is cached history only: listing servers must never open SSH sessions.
  def resource_summary
    sample = server_metrics.order(sampled_at: :desc).first
    (sample&.data || { "available" => false }).slice("available", "cpu", "memory", "disk", "memory_used", "memory_total", "disk_used", "disk_total", "cpu_cores").merge("sampled_at" => sample&.sampled_at&.iso8601, "collection_enabled" => ObservabilitySettings.hosts_enabled?)
  end

  private

  def ssh_key_format
    result = SshKeyValidator.validate(ssh_key)
    errors.add(:ssh_key, result[:error]) unless result[:valid]
  end
end
