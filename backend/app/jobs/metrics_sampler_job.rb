# frozen_string_literal: true

# Samples live resource usage for every deployed container and persists it
# to service_metrics for historical graphs. Runs every 5 minutes via
# recurring.yml. Also prunes samples older than ServiceMetric::RETENTION.
class MetricsSamplerJob < ApplicationJob
  queue_as :default

  def perform(now: Time.current)
    # Sample each connected server's app containers in one pass.
    Server.where.not(ssh_key_ciphertext: [ nil, "" ]).find_each do |server|
      host_engine = HostEngine.new(server)

      server.projects.each do |project|
        project.services.each do |service|
          next unless service.docker_image.present?

          sample_service(host_engine, service, now)
        rescue => e
          Rails.logger.warn "Metrics sample failed for #{service.dokku_app_name}: #{e.message}"
        end
      end
    end

    ServiceMetric.prune_older_than!
  end

  private

  def sample_service(host_engine, service, now)
    container = host_engine.dokku_container_name(service.dokku_app_name)
    return unless container.present?

    stats = host_engine.docker_stats(container)
    return unless stats

    service.service_metrics.create!(
      cpu: stats[:cpu],
      memory: stats[:memory],
      memory_used: stats[:memory_used],
      memory_limit: stats[:memory_limit],
      network_in: 0,
      network_out: 0,
      sampled_at: now
    )
  end
end
