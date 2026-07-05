class PluginSetting < ApplicationRecord
  belongs_to :plugin

  validates :key, presence: true, uniqueness: { scope: :plugin_id }
  validates :value, presence: true, if: -> { required? }

  def required?
    return false if key.blank?

    schema = plugin.config_schema || {}
    field = schema[key.to_s] || schema[key.to_sym]
    field&.dig(:required) == true
  end
end
