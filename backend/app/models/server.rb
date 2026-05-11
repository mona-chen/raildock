class Server < ApplicationRecord
  has_many :projects, dependent: :nullify

  validates :name, presence: true
  validates :host, presence: true

  # Manual lockbox encryption for ssh_key to avoid ActiveRecord attribute
  # method conflicts with the legacy plaintext column. Uses base64-encoded
  # ciphertext so it can be stored in a text column without null byte issues.
  def ssh_key
    ciphertext = self[:ssh_key_ciphertext]
    return nil if ciphertext.blank?

    lockbox.decrypt(ciphertext)
  rescue Lockbox::DecryptionError
    nil
  end

  def ssh_key=(value)
    if value.present?
      self[:ssh_key_ciphertext] = lockbox.encrypt(value)
    else
      self[:ssh_key_ciphertext] = nil
    end
  end

  private

  def lockbox
    @lockbox ||= Lockbox.new(key: Lockbox.master_key, encode: true)
  end

  public

  enum :status, {
    connected: "connected",
    disconnected: "disconnected",
    error: "error"
  }, default: "disconnected"

  PROXY_TYPES = %w[nginx traefik caddy haproxy openresty].freeze

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
      methods: [:disk_usage, :memory_usage, :project_ids, :default_proxy],
      except: [:ssh_key_ciphertext]
    ))
  end
end
