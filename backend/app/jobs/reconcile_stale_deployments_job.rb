class ReconcileStaleDeploymentsJob < ApplicationJob
  queue_as :default

  PENDING_TIMEOUT = 30.minutes
  RUNNING_TIMEOUT = 2.hours

  def perform(now: Time.current)
    fail_stale(Deployment.pending.where("started_at < ?", now - PENDING_TIMEOUT), now, "Deployment timed out waiting for a worker")
    fail_stale(
      Deployment.where(status: %i[building deploying]).where("started_at < ?", now - RUNNING_TIMEOUT),
      now,
      "Deployment exceeded the maximum execution time"
    )
  end

  private

  def fail_stale(scope, now, message)
    scope.find_each do |deployment|
      deployment.update!(
        status: :failed,
        deploy_log: [ deployment.deploy_log.presence, message ].compact.join("\n\n"),
        completed_at: now
      )

      service = deployment.service
      active = service.deployments.where(status: %i[pending building deploying]).exists?
      service.update!(status: active ? :deploying : :error)

      DeploymentsChannel.broadcast_to(service, {
        deployment_id: deployment.id,
        status: "failed",
        message: message,
        completed_at: now.iso8601
      })
    end
  end
end
