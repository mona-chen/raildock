class Domain < ApplicationRecord
  belongs_to :service

  before_validation :normalize_hostname

  validates :hostname, presence: true, uniqueness: { scope: :service_id, case_sensitive: false }
  validates :port, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65535 }
  validates :target_port, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65535 }
  validates :ssl_status, inclusion: { in: %w[none pending active failed] }
  validates :challenge_type, inclusion: { in: %w[http dns] }

  scope :with_ssl, -> { where(ssl: true) }
  scope :ssl_pending, -> { where(ssl_status: "pending") }

  MAGIC_DOMAINS = %w[sslip.io nip.io traefik.me].freeze

  def wildcard?
    hostname.to_s.start_with?("*.")
  end

  def as_json(options = {})
    super(options.merge(
      methods: [ :temporary, :wildcard, :base_hostname, :traefik_rule ]
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
