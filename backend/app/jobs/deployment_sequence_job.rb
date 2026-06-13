class DeploymentSequenceJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: ->(entries) {
    ids = entries.map { |entry| entry["deployment_id"] || entry[:deployment_id] }.sort
    "deploy-sequence:#{ids.join("-")}"
  }

  def perform(entries)
    entries.map(&:with_indifferent_access).each do |entry|
      deployment = Deployment.find_by(id: entry[:deployment_id], service_id: entry[:service_id])
      next unless deployment&.pending?

      failed_dependency = Array(entry[:depends_on_deployment_ids]).filter_map do |deployment_id|
        dependency = Deployment.find_by(id: deployment_id)
        dependency unless dependency&.succeeded?
      end.first

      if failed_dependency
        cancel(deployment, "Dependency deployment #{failed_dependency.id} did not succeed")
      else
        DeploymentJob.perform_now(deployment.service_id, deployment.id)
      end
    end
  end

  private
    def cancel(deployment, message)
      deployment.update!(
        status: :cancelled,
        deploy_log: message,
        completed_at: Time.current
      )

      service = deployment.service
      active = service.deployments.where(status: %i[ pending building deploying ]).exists?
      service.update!(status: active ? :deploying : :error)

      DeploymentsChannel.broadcast_to(service, {
        deployment_id: deployment.id,
        status: "cancelled",
        message: message,
        completed_at: deployment.completed_at.iso8601
      })
    end
end
