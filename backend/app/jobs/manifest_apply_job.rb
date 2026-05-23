# frozen_string_literal: true

# Applies manifest changes to a project.
# Runs in dependency order: databases → apps → links.
# Groups changes by severity and applies in batches.
class ManifestApplyJob < ApplicationJob
  queue_as :default

  def perform(project_id, content = nil)
    project = Project.find_by(id: project_id)
    return unless project

    content ||= project.manifest_content
    format = project.manifest_format || "raildock.toml"
    return unless content.present?

    desired = ManifestParser.parse(content, filename: format)
    reconciler = ManifestReconciler.new(project, desired)
    reconciler.diff

    server = project.server
    unless server&.ssh_key.present?
      broadcast(project_id, "error", "No server SSH key configured")
      return
    end

    engine = DokkuEngine.new(server)
    broadcast(project_id, "started", "Applying manifest changes...")

    result = reconciler.apply!(engine)

    if result[:success]
      project.update!(
        manifest_last_applied_at: Time.current,
        manifest_drift_detected: false
      )
      broadcast(project_id, "completed", "All manifest changes applied successfully")
    else
      failed = result[:results]&.select { |r| !r[:success] } || []
      broadcast(project_id, "failed", "Some changes failed", details: failed.map { |f| f[:error] })
    end
  rescue => e
    Rails.logger.error "ManifestApplyJob failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
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
    ActionCable.server.broadcast("project_#{project_id}", payload)
  end
end
