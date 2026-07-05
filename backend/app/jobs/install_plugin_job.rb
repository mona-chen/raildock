# frozen_string_literal: true

class InstallPluginJob < ApplicationJob
  queue_as :default

  def perform(source_url:, source_type: "remote", source_ref: nil)
    manifest = PluginManifest.new(source_url)
    data = manifest.fetch

    if data.nil? || manifest.errors.any?
      Rails.logger.error "Plugin install failed for #{source_url}: #{manifest.errors.join(", ")}"
      raise "Manifest fetch/validation failed: #{manifest.errors.join(", ")}"
    end

    data[:source_type] = source_type if source_type.present?
    data[:source_url] = source_url
    data[:source_ref] = source_ref if source_ref.present?

    plugin = PluginRegistry.register_external!(data)
    PluginRegistry.clear_cache!

    Rails.logger.info "Installed plugin #{plugin.slug} (#{plugin.name}) from #{source_url}"
    plugin
  rescue => e
    Rails.logger.error "InstallPluginJob failed: #{e.message}"
    raise
  end
end
