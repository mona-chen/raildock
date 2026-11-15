class MonitoringTickJob < ApplicationJob
  queue_as :observability
  def perform
    Server.find_each do |server|
      CollectHttpTrafficJob.perform_later(server.id) if server.traffic_settings["enabled"] == true
      MonitoringEvaluator.call(server) if server.organization_id
      retention = server.traffic_settings.fetch("retention_days", 7).to_i.clamp(1, 30)
      server.http_traffic_buckets.where(resolution: "minute").where("bucket_at < ?", [ retention, 2 ].min.days.ago).in_batches.delete_all
      server.http_traffic_buckets.where(resolution: "hour").where("bucket_at < ?", retention.days.ago).in_batches.delete_all
      days = MonitoringPolicy.for(server.organization).fetch("retention_days")
      server.monitoring_incidents.where.not(resolved_at: nil).where("resolved_at < ?", days.days.ago).in_batches.delete_all
    rescue ApplicationController::AuthorizationDenied, ServiceOperationLock::Busy
      raise
    rescue => e
      Rails.logger.warn "Monitoring tick failed for server #{server.id}: #{e.class}"
    end
  end
end
