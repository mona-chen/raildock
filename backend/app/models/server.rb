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
    super(options.merge(methods: [:disk_usage, :memory_usage, :project_ids, :default_proxy]))
  end
end
