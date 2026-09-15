# frozen_string_literal: true

# Applies manifest changes to a project.
# Runs in dependency order: databases → apps → links.
# Groups changes by severity and applies in batches.
class ManifestApplyJob < ApplicationJob
  queue_as :default

  # options:
  #   allow_removals:     opt-in to destroying services that the manifest omits.
  #                       Only set after the user confirmed the exact list.
  #   force_destroy_data: proceed without a verified pre-destroy snapshot.
  def perform(project_id, content = nil, options = {})
    options = (options || {}).symbolize_keys
    allow_removals = ActiveModel::Type::Boolean.new.cast(options[:allow_removals]) || false
    force_destroy_data = ActiveModel::Type::Boolean.new.cast(options[:force_destroy_data]) || false

    project = Project.find_by(id: project_id)
    unless project
      Rails.logger.warn "ManifestApplyJob: project #{project_id} not found"
      return
    end

    content ||= project.manifest_content
    format = project.manifest_format || "raildock.toml"
    unless content.present?
      broadcast(project_id, "failed", "No manifest content to apply")
      return
    end

    desired = ManifestParser.parse(content, filename: format)

    schema_content = desired.repaired_content || content
    parsed = JSON.parse(schema_content) rescue (TomlRB.parse(schema_content) rescue nil)
    if parsed
      validation = ManifestSchema.validate(parsed)
      unless validation.success?
        broadcast(project_id, "failed", "Manifest validation failed", details: validation.errors)
        ActivityEvent.create!(
          project: project,
          service_name: "-",
          action: :warning,
          message: "Manifest validation failed: #{validation.errors.join('; ')}"
        )
        return
      end
    end

    reconciler = ManifestReconciler.new(project, desired)
    reconciler.diff

    server = project.server
    unless server&.ssh_key.present?
      broadcast(project_id, "error", "No server SSH key configured")
      return
    end

    engine = DokkuEngine.new(server)
    host_engine = HostEngine.new(server)
    broadcast(project_id, "started", "Applying manifest changes...")

    result = engine.with_session do
      host_engine.with_session do
        reconciler.apply!(
          engine,
          host_engine: host_engine,
          allow_removals: allow_removals,
          force_destroy_data: force_destroy_data
        )
      end
    end

    report_withheld_removals(project, project_id, result)

    if result[:success]
      project.update!(
        manifest_last_applied_at: Time.current,
        manifest_drift_detected: drift_after_apply?(project, content, result)
      )
      broadcast(project_id, "completed", "All manifest changes applied successfully")
    else
      failed = result[:results]&.select { |r| !r[:success] } || []
      error_details = failed.map { |f| f[:error] }.compact.join("; ")
      ActivityEvent.create!(
        project: project,
        service_name: "-",
        action: :warning,
        message: "Manifest apply failed: #{error_details}"
      )
      broadcast(project_id, "failed", "Some changes failed", details: failed.map { |f| f[:error] })
    end
  rescue => e
    Rails.logger.error "ManifestApplyJob failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    ActivityEvent.create!(
      project: project,
      service_name: "-",
      action: :warning,
      message: "Manifest apply error: #{e.message}"
    ) if project
    broadcast(project_id, "failed", e.message)
  end

  private

  # "No drift" means the stored manifest describes what was actually applied.
  # Clearing the flag unconditionally would erase the warning raised when an
  # apply deliberately kept services the manifest omits — leaving the project
  # with a manifest that no longer matches it and no indication of that.
  def drift_after_apply?(project, content, result)
    withheld = Array(result[:skipped_removals]).any? || Array(result[:blocked_removals]).any?
    withheld || project.manifest_content.to_s != content.to_s
  end

  # Removals that were intentionally not performed. Surfaced loudly so a
  # manifest that drops a service is never mistaken for a completed clean-up.
  def report_withheld_removals(project, project_id, result)
    skipped = Array(result[:skipped_removals])
    blocked = Array(result[:blocked_removals])
    return if skipped.empty? && blocked.empty?

    if skipped.any?
      broadcast(
        project_id,
        "warning",
        "#{skipped.length} service#{'s' if skipped.length != 1} kept: #{skipped.join(', ')}",
        details: [ "Removals require explicit confirmation before RailDock deletes them." ]
      )
    end

    if blocked.any?
      broadcast(
        project_id,
        "warning",
        "Removals skipped after failures: #{blocked.join(', ')}",
        details: [ "Nothing was deleted because earlier manifest changes did not succeed." ]
      )
    end
  end

  def broadcast(project_id, status, message, details: nil)
    payload = {
      type: "manifest_apply",
      status: status,
      message: message,
      timestamp: Time.current.iso8601
    }
    payload[:details] = details if details
    project = Project.find_by(id: project_id)
    RealtimeBroadcaster.project(project, payload) if project
  end
end
