class Server < ApplicationRecord
  has_many :projects, dependent: :nullify
  has_many :backup_destinations, dependent: :destroy
  belongs_to :user, optional: true
  belongs_to :organization, optional: true

  validates :name, presence: true
  validates :host, presence: true

  enum :status, {
    connected: "connected",
    disconnected: "disconnected",
    error: "error"
  }, default: "disconnected"

  PROXY_TYPES = %w[nginx traefik caddy haproxy openresty].freeze
  PROXY_MODES = %w[managed external].freeze

  validates :proxy_mode, inclusion: { in: PROXY_MODES }
  validates :external_proxy_network, presence: true, if: :external_proxy?

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
      methods: [ :disk_usage, :memory_usage, :project_ids, :default_proxy, :ssh_user, :base_domain, :auto_domains ],
      except: [ :ssh_key_ciphertext, :host_key ]
    ))
  end
end
