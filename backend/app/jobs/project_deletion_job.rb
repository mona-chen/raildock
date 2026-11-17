# Long-running snapshots and SSH teardown must outlive the HTTP request.
class ProjectDeletionJob < ApplicationJob
  # Destructive teardown is isolated from deployments and from the data-safety
  # queue: it can hold a project lock for a long time, and it must never delay a
  # deploy or another PITR WAL archive.
  queue_as :maintenance
  retry_on ServiceOperationLock::Busy, wait: 5.seconds, attempts: 60 do |job, error|
    project = Project.find_by(id: job.arguments.first)
    project&.update!(deletion_status: "failed", deletion_error: error.message)
  end

  def perform(project_id, force_destroy_data: false)
    project = Project.find_by(id: project_id)
    # A stalled request is still its only owner: duplicates are serialized by the
    # project lock, so finishing it is safer than leaving the row wedged.
    return unless project&.deletion_requested?

    ServiceOperationLock.with_project(project, exclusive: true, allow_deletion: true) do
      project.reload
      return unless project.deletion_requested?

      project.update!(deletion_status: "running", deletion_requested_at: Time.current)
      snapshot = DestructionSnapshot.capture_all(project.services.to_a)
      if snapshot[:errors].any? && !force_destroy_data
        project.update!(deletion_status: "failed", deletion_error_code: "snapshot_required",
          deletion_error: "Deletion stopped: #{snapshot[:errors].join('; ')}. Configure a verified backup destination, or explicitly acknowledge permanent data loss.")
        return
      end
      if snapshot[:errors].any?
        ActivityEvent.create!(project: project, service_name: "-", action: :warning,
          message: "Deleting #{project.name} without complete snapshots: #{snapshot[:errors].join('; ')}")
      end
      project.destroy_with_resources!(confirmed: true)
    end
  rescue ServiceOperationLock::Busy
    raise
  rescue StandardError => error
    project&.reload&.update!(deletion_status: "failed", deletion_error_code: "resources_not_removed",
      deletion_error: error.message)
  end
end
