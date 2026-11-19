# frozen_string_literal: true

# Applies manifest changes to a project.
# Runs in dependency order: databases → apps → links.
# Groups changes by severity and applies in batches.
class ManifestApplyJob < ApplicationJob
  queue_as :default
  retry_on ServiceOperationLock::Busy, wait: 5.seconds, attempts: 60

  # options:
  #   allow_removals:     opt-in to destroying services that the manifest omits.
  #                       Only set after the user confirmed the exact list.
  #   force_destroy_data: proceed without a verified pre-destroy snapshot.
  #   service_names:      optional subset of the manifest's services to apply.
  #                       Used when a repository import only deploys the
  #                       services the user selected.
  #   operation_id:       the Operation row the API returned to the caller.
  #   api_token_id:       the token that started the apply, recorded on the
  #                       activity events this job writes.
  def perform(project_id, content = nil, options = {})
    options = (options || {}).symbolize_keys
    allow_removals = ActiveModel::Type::Boolean.new.cast(options[:allow_removals]) || false
    force_destroy_data = ActiveModel::Type::Boolean.new.cast(options[:force_destroy_data]) || false
    service_names = options.key?(:service_names) ? Array(options[:service_names]).map(&:to_s).uniq : nil
    operation = Operation.find_by(id: options[:operation_id])
    api_token_id = options[:api_token_id].presence || operation&.api_token_id
    operation&.update!(status: "running")

    project = Project.find_by(id: project_id)
    unless project
      finish_operation(operation, "failed", "Project not found")
      Rails.logger.warn "ManifestApplyJob: project #{project_id} not found"
      return
    end

    content ||= project.manifest_content
    format = project.manifest_format || "raildock.toml"
    unless content.present?
      finish_operation(operation, "failed", "No manifest content to apply")
      broadcast(project_id, "failed", "No manifest content to apply")
      return
    end

    desired = ManifestParser.parse(content, filename: format)

    if service_names
      unknown = service_names - desired.service_names.map(&:to_s)
      if service_names.empty? || unknown.any?
        message = service_names.empty? ? "No services selected to deploy" : "Unknown services selected: #{unknown.join(', ')}"
        finish_operation(operation, "failed", message)
        broadcast(project_id, "failed", message)
        return
      end
    end

    schema_content = desired.repaired_content || content
    parsed = JSON.parse(schema_content) rescue (TomlRB.parse(schema_content) rescue nil)
    if parsed
      validation = ManifestSchema.validate(parsed)
      unless validation.success?
        finish_operation(operation, "failed", "Manifest validation failed: #{validation.errors.join('; ')}")
        broadcast(project_id, "failed", "Manifest validation failed", details: validation.errors)
        ActivityEvent.create!(
          project: project,
          service_name: "-",
          action: :warning,
          message: "Manifest validation failed: #{validation.errors.join('; ')}",
          api_token_id: api_token_id
        )
        return
      end
    end

    reconciler = ManifestReconciler.new(project, desired, only: service_names)
    reconciler.diff

    server = project.server
    unless server&.ssh_key.present?
      finish_operation(operation, "failed", "No server SSH key configured")
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
          manifest_digest: RemovalConfirmation.digest_for(content),
          force_destroy_data: force_destroy_data
        )
      end
    end

    report_withheld_removals(project, project_id, result)

    if result[:success]
      if result[:operation_id]
        # Removals are deferred until their deployments succeed. Point the
        # operation at the ManifestOperation so its status keeps coming from the
        # finalizer instead of being copied here.
        operation&.update!(
          subject_type: "ManifestOperation",
          subject_id: result[:operation_id],
          status: "running"
        )
        broadcast(project_id, "deploying", "Waiting for deployments before removing services", details: result[:pending_removals])
      else
        project.update!(manifest_last_applied_at: Time.current, manifest_drift_detected: drift_after_apply?(project, content, result))
        finish_operation(operation, "succeeded")
        broadcast(project_id, "completed", "All manifest changes applied successfully")
      end
    else
      failed = result[:results]&.select { |r| !r[:success] } || []
      error_details = failed.map { |f| f[:error] }.compact.join("; ")
      finish_operation(operation, "failed", error_details.presence || "Some manifest changes failed")
      ActivityEvent.create!(
        project: project,
        service_name: "-",
        action: :warning,
        message: "Manifest apply failed: #{error_details}",
        api_token_id: api_token_id
      )
      broadcast(project_id, "failed", "Some changes failed", details: failed.map { |f| f[:error] })
    end
  rescue ServiceOperationLock::Busy
    raise
  rescue => e
    Rails.logger.error "ManifestApplyJob failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    finish_operation(operation, "failed", e.message)
    ActivityEvent.create!(
      project: project,
      service_name: "-",
      action: :warning,
      message: "Manifest apply error: #{e.message}",
      api_token_id: api_token_id
    ) if project
    broadcast(project_id, "failed", e.message)
  end

  private

  def finish_operation(operation, status, error = nil)
    return unless operation

    attributes = { status: status, completed_at: Time.current }
    attributes[:error] = error if error.present?
    operation.update!(attributes)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn "ManifestApplyJob: could not update operation #{operation.id}: #{e.message}"
  end

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
