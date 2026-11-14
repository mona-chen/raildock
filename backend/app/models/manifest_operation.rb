# Durable continuation for the destructive phase of a manifest apply. The exact
# service identities are captured before enqueueing; never re-diff a later manifest.
class ManifestOperation < ApplicationRecord
  belongs_to :project
  after_update_commit :broadcast_finished

  validates :status, inclusion: { in: %w[waiting finalizing succeeded failed] }

  def finalize_if_ready!
    with_lock do
      return unless status == "waiting"

      if manifest_digest.present? && manifest_digest != RemovalConfirmation.digest_for(project.reload.manifest_content.to_s)
        update!(status: "failed", error: "Manifest revision changed; removals were blocked", completed_at: Time.current)
        return
      end
      deployments = Deployment.where(id: deployment_ids, service_id: project.services.select(:id)).to_a
      if deployments.size != deployment_ids.size || deployments.any? { |deployment| deployment.failed? || deployment.cancelled? }
        update!(status: "failed", error: "A required deployment failed, was cancelled, or disappeared; removals were blocked", completed_at: Time.current)
        return
      end
      return unless deployments.all?(&:succeeded?)

      update!(status: "finalizing")
      desired = ManifestParser::ManifestDesiredState.new(services: [], links: [], format_detected: "raildock.toml")
      reconciler = ManifestReconciler.new(project, desired)
      results = reconciler.finish_confirmed_removals!(DokkuEngine.new(project.server), removals, force_destroy_data: force_destroy_data)
      errors = results.reject { |result| result[:success] }.map { |result| result[:error] }
      if errors.empty? && manifest_digest.present? && manifest_digest == RemovalConfirmation.digest_for(project.manifest_content.to_s)
        project.update!(manifest_last_applied_at: Time.current, manifest_drift_detected: false)
      end
      update!(status: errors.empty? ? "succeeded" : "failed", error: errors.presence&.join("; "), completed_at: Time.current)
    end
  end
  private

  def broadcast_finished
    return unless saved_change_to_status? && %w[succeeded failed].include?(status)

    message = status == "succeeded" ? "Manifest deployments and confirmed removals completed" : error
    RealtimeBroadcaster.project(project, { type: "manifest_apply", status: status == "succeeded" ? "completed" : "failed", message: message })
    ActivityEvent.create!(project: project, service_name: "-", action: status == "succeeded" ? :deployed : :warning, message: message)
  end
end
