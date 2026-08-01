class ReconcileStaleDeploymentsJob < ApplicationJob
  queue_as :default

  PENDING_TIMEOUT = 30.minutes
  RUNNING_TIMEOUT = 2.hours
  STALE_UPCOMING_AGE = 1.hour

  def perform(now: Time.current)
    fail_stale(
      Deployment.pending.where("COALESCE(started_at, created_at) < ?", now - PENDING_TIMEOUT),
      now,
      "Deployment timed out waiting for a worker"
    )
    fail_stale(
      Deployment.where(status: %i[building deploying]).where("started_at < ?", now - RUNNING_TIMEOUT),
      now,
      "Deployment exceeded the maximum execution time"
    )

    prune_stale_upcoming_containers
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

      RealtimeBroadcaster.deployment(service, {
        deployment_id: deployment.id,
        status: "failed",
        message: message,
        completed_at: now.iso8601
      })
    end
  end

  def prune_stale_upcoming_containers
    Server.where.not(ssh_key_ciphertext: [ nil, "" ]).find_each do |server|
      result = HostEngine.new(server).prune_stale_upcoming_containers(older_than: STALE_UPCOMING_AGE)
      next unless result[:success] && result[:removed].positive?

      Rails.logger.info "Pruned #{result[:removed]} stale upcoming container(s) on server #{server.name}"
    end
  rescue => e
    Rails.logger.warn "Stale upcoming container prune sweep failed: #{e.message}"
  end
end
