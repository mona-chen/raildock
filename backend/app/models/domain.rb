class Domain < ApplicationRecord
  belongs_to :service

  before_validation :normalize_hostname

  validates :hostname, presence: true, uniqueness: { scope: :service_id, case_sensitive: false }
  validates :port, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65535 }
  # A blank target_port means "follow the app" — resolve it through
  # #resolved_target_port rather than storing a snapshot, which is what let a
  # domain keep pointing at 5000 (or 80) long after the app's port changed.
  validates :target_port, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65535 }, allow_nil: true
  validates :ssl_status, inclusion: { in: %w[none pending active failed] }
  validates :challenge_type, inclusion: { in: %w[http dns] }

  scope :with_ssl, -> { where(ssl: true) }
  scope :ssl_pending, -> { where(ssl_status: "pending") }

  MAGIC_DOMAINS = %w[sslip.io nip.io traefik.me].freeze

  # The container port this hostname should route to. An explicit target_port
  # is a per-domain override; otherwise the domain follows the service's
  # effective (actually listening) port.
  def resolved_target_port
    target_port.presence || service&.effective_port || 5000
  end

  def wildcard?
    hostname.to_s.start_with?("*.")
  end

  def as_json(options = {})
    super(options.merge(
      methods: [ :temporary, :wildcard, :base_hostname, :traefik_rule, :resolved_target_port ]
    ))
  end

  def base_hostname
    hostname.to_s.sub(/^\*\./, "")
  end

  def traefik_rule
    if wildcard?
      escaped_base = base_hostname.gsub(".", '\\.')
      "HostRegexp(`^[a-z0-9-]+\\.#{escaped_base}$`)"
    else
      "Host(`#{hostname}`)"
    end
  end

  private

  def normalize_hostname
    self.hostname = hostname.to_s
      .strip
      .sub(%r{\Ahttps?://?}i, "")
      .sub(%r{:\d+\z}, "")
      .sub(%r{/.*\z}, "")
      .downcase
      .presence
  end

  def magic_domain?
    MAGIC_DOMAINS.any? { |m| hostname.to_s.end_with?("." + m) }
  end

  def ssl_active?
    ssl_status == "active"
  end

  def ssl_pending?
    ssl_status == "pending"
  end

  def ssl_failed?
    ssl_status == "failed"
  end
end
