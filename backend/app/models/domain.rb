class Domain < ApplicationRecord
  belongs_to :service

  validates :hostname, presence: true, uniqueness: { scope: :service_id }
  validates :port, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65535 }
  validates :target_port, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65535 }

  def wildcard?
    hostname.to_s.start_with?('*.')
  end

  def base_hostname
    hostname.to_s.sub(/^\*\./, '')
  end

  def traefik_rule
    if wildcard?
      # Match any single-level subdomain (alphanumeric + hyphens)
      # Escape dots in the base domain for the regex
      escaped_base = base_hostname.gsub('.', '\\.')
      "HostRegexp(`^[a-z0-9-]+\\.#{escaped_base}$`)"
    else
      "Host(`#{hostname}`)"
    end
  end

  def as_json(options = {})
    super(options.merge(
      methods: [:temporary, :wildcard, :base_hostname, :traefik_rule]
    ))
  end
end
