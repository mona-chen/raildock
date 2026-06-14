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
        deployment.cancel!(message: "Dependency deployment #{failed_dependency.id} did not succeed")
      else
        DeploymentJob.perform_now(deployment.service_id, deployment.id)
      end
    end
  end
end
