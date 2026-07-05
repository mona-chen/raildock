# frozen_string_literal: true

class UninstallPluginJob < ApplicationJob
  queue_as :default

  def perform(plugin_id)
    plugin = Plugin.find(plugin_id)

    if plugin.built_in?
      Rails.logger.warn "Cannot uninstall built-in plugin #{plugin.slug}"
      raise "Built-in plugins cannot be uninstalled"
    end

    in_use_subtypes = plugin.service_subtypes.pluck(:subtype)
    in_use_builders = plugin.builders.pluck(:slug)

    if Service.where(subtype: in_use_subtypes).any?
      raise "Plugin subtypes are still in use by services"
    end

    if Service.where(builder: in_use_builders).any?
      raise "Plugin builders are still in use by services"
    end

    if plugin.uninstall_command.present?
      Rails.logger.info "Running uninstall command for #{plugin.slug}: #{plugin.uninstall_command}"
      # Host-side execution is a future enhancement; for now we only log the command.
    end

    PluginRegistry.unregister!(plugin)
    PluginRegistry.clear_cache!

    Rails.logger.info "Uninstalled plugin #{plugin.slug}"
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "UninstallPluginJob could not find plugin #{plugin_id}"
  end
end
