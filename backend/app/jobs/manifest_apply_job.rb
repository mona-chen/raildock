# frozen_string_literal: true

# Applies manifest changes to a project.
# Runs in dependency order: databases → apps → links.
# Groups changes by severity and applies in batches.
class ManifestApplyJob < ApplicationJob
  queue_as :default

  def perform(project_id, content = nil)
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
        reconciler.apply!(engine, host_engine: host_engine)
      end
    end

    if result[:success]
      project.update!(
        manifest_last_applied_at: Time.current,
        manifest_drift_detected: false
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
