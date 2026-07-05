class ServiceSubtype < ApplicationRecord
  belongs_to :plugin
  has_many :services, foreign_key: "subtype", primary_key: "subtype", dependent: nil, inverse_of: :service_subtype

  validates :subtype, presence: true, uniqueness: true
  validates :name, presence: true
  validates :service_type, presence: true, inclusion: { in: %w[app database cache queue search service] }
  validates :dokku_plugin, presence: true, if: -> { capabilities.include?("create") }

  scope :for_service_type, ->(type) { where(service_type: type) }
  scope :with_capability, ->(capability) { where("capabilities @> ?", [ capability.to_s ].to_json) }

  def has_capability?(capability)
    Array(capabilities).map(&:to_s).include?(capability.to_s)
  end

  def dokku_command(action)
    namespace = command_namespace.presence || dokku_plugin
    return nil if namespace.blank?

    "#{namespace}:#{action}"
  end

  def default_image
    metadata["default_image"]
  end

  def url_var
    env_var_prefix.presence || metadata["url_var"]
  end

  def sslmode
    metadata["sslmode"]
  end

  def url_scheme
    metadata["url_scheme"]
  end
end
