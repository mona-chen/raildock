# frozen_string_literal: true

# Samples live resource usage for every deployed container and persists it
# to service_metrics for historical graphs. Runs every minute via
# recurring.yml. Also prunes samples older than ServiceMetric::RETENTION.
class MetricsSamplerJob < ApplicationJob
  queue_as :default

  def perform(now: Time.current)
    # Sample each connected server's app containers in one pass.
    Server.where.not(ssh_key_ciphertext: [ nil, "" ]).find_each do |server|
      host_engine = HostEngine.new(server)

      HostMetricsCollector.call(server, now: now) if ObservabilitySettings.hosts_enabled?
      next unless ObservabilitySettings.services_enabled?

      snapshot = host_engine.docker_stats_snapshot
      prefixes = ServiceSubtype.where.not(dokku_plugin: nil).distinct.pluck(:dokku_plugin).map { |plugin| "dokku.#{plugin}." }
      server.projects.each do |project|
        project.services.each do |service|
          next unless service.running?

          names = [ "#{service.dokku_app_name}.web.1", *prefixes.map { |prefix| "#{prefix}#{service.dokku_app_name}" } ]
          stats = names.filter_map { |name| snapshot[name] }.first
          sample_service(service, stats, now) if stats
        rescue => e
          Rails.logger.warn "Metrics sample failed for #{service.dokku_app_name}: #{e.message}"
        end
      end
    rescue ApplicationController::AuthorizationDenied, ServiceOperationLock::Busy
      raise
    rescue => e
      Rails.logger.warn "Metrics collection failed for server #{server.id}: #{e.class}"
    end

    ServiceMetric.prune_older_than!
    ServerMetric.prune_older_than!
  end

  private

  def sample_service(service, stats, now)
    service.service_metrics.create!(
      cpu: stats[:cpu],
      cpu_cores: stats[:cpu_cores],
      memory: stats[:memory],
      memory_used: stats[:memory_used],
      memory_limit: stats[:memory_limit],
      network_in: stats[:network_rx] || 0,
      network_out: stats[:network_tx] || 0,
      block_read: stats[:block_read] || 0,
      block_write: stats[:block_write] || 0,
      sampled_at: now
    )
  end
end
