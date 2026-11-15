require "base64"

# One SSH round trip per host, coalesced across viewers and workers for ten
# seconds using a nonblocking advisory lock. Background collection continues every minute.
class HostMetricsCollector
  FIELDS = %w[cpu memory disk load uptime_seconds network_rx network_tx].freeze

  def self.call(server, now: Time.current)
    ApplicationRecord.connection_pool.with_connection do |connection|
      key = "hashtextextended('raildock:host-metrics:#{Integer(server.id)}', 0)"
      acquired = connection.select_value("SELECT pg_try_advisory_lock(#{key})")
      return server.server_metrics.order(sampled_at: :desc).first unless acquired

      begin
        recent = server.server_metrics.order(sampled_at: :desc).first
        return recent if recent && recent.sampled_at > now - 10.seconds
        return nil unless ObservabilitySettings.hosts_enabled?

        server.server_metrics.create!(sampled_at: now, data: collect(server))
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{key})")
      end
    end
  end

  def self.collect(server)
    return { "available" => false, "reason" => "SSH is not configured" } if server.ssh_key.blank?

    script = Base64.strict_encode64(File.binread(Rails.root.join("lib/raildock/host_metrics.sh")))
    result = HostEngine.new(server).run("printf '%s' '#{script}' | base64 -d | sh")
    return { "available" => false, "reason" => "Host collection failed" } unless result[:success]

    data = result[:output].to_s.lines.to_h do |line|
      key, value = line.split
      [ key, Float(value, exception: false) ]
    end.slice(*FIELDS)
    return { "available" => false, "reason" => "Host returned incomplete metrics" } unless FIELDS.all? { |field| data[field]&.finite? && data[field] >= 0 }

    data.merge("available" => true)
  rescue ApplicationController::AuthorizationDenied, ServiceOperationLock::Busy
    raise
  rescue StandardError => e
    Rails.logger.warn("Host metrics collection failed for server #{server.id}: #{e.class}")
    { "available" => false, "reason" => "Host collection failed" }
  end
end
