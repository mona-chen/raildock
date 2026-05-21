class Server < ApplicationRecord
  has_many :projects, dependent: :nullify

  validates :name, presence: true
  validates :host, presence: true

  enum :status, {
    connected: "connected",
    disconnected: "disconnected",
    error: "error"
  }, default: "disconnected"

  PROXY_TYPES = %w[nginx traefik caddy haproxy openresty].freeze

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

  def disk_usage
    { used: disk_used || 0, total: disk_total || 100 }
  end

  def memory_usage
    { used: memory_used || 0, total: memory_total || 128 }
  end

  def project_ids
    projects.pluck(:id)
  end

  def as_json(options = {})
    super(options.merge(
      methods: [:disk_usage, :memory_usage, :project_ids, :default_proxy, :ssh_user],
      except: [:ssh_key_ciphertext]
    ))
  end
end