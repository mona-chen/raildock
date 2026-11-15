class MonitoringEvaluator
  def self.call(server, now: Time.current)
    policy = MonitoringPolicy.for(server.organization)
    return unless policy["enabled"]

    # One evaluation per server at a time, independent of sampling/viewers.
    ApplicationRecord.connection_pool.with_connection do |connection|
      key = "hashtextextended('raildock:monitoring:#{Integer(server.id)}', 0)"
      return unless connection.select_value("SELECT pg_try_advisory_lock(#{key})")
      begin
        recent = server.server_metrics.where(sampled_at: 2.minutes.ago..).order(sampled_at: :desc).first
        if ObservabilitySettings.hosts_enabled?
          transition(server, "host_unavailable", recent.nil? || !recent.data["available"], "Host metrics unavailable", policy, now)
          %w[cpu memory disk].each do |signal|
            next unless recent&.data&.fetch("available", false)
            threshold = policy.fetch(signal)
            active = server.monitoring_incidents.where(signal: signal, resolved_at: nil, state: "firing").exists?
            # Five percentage points of hysteresis avoids flapping at a boundary.
            breached = threshold.positive? && recent.data[signal].to_f >= threshold - (active ? 5 : 0)
            transition(server, signal, breached, "Host #{signal} usage exceeds #{threshold}%", policy, now)
          end
        end
        if ObservabilitySettings.services_enabled?
          projects = server.projects.includes(:services)
          ids = projects.flat_map { |project| project.services.map(&:id) }
          latest = ServiceMetric.where(service_id: ids, sampled_at: 2.minutes.ago..)
            .select("DISTINCT ON (service_id) service_metrics.*").order(:service_id, sampled_at: :desc).index_by(&:service_id)
          projects.each do |project|
            project.services.each do |service|
              next if service.stopped?
              sample = latest[service.id]
              transition(server, "service_#{service.id}_unavailable", sample.nil?, "Application #{service.name} metrics unavailable", policy, now)
              next unless sample
              { "cpu" => sample.cpu.to_f / (sample.cpu_cores.to_f.positive? ? sample.cpu_cores : 1), "memory" => sample.memory }.each do |signal, value|
                next if value.nil?
                threshold = policy.fetch(signal)
                transition(server, "service_#{service.id}_#{signal}", threshold.positive? && value >= threshold, "Application #{service.name} #{signal} usage exceeds #{threshold}%", policy, now)
              end
            end
          end
        end
        if server.traffic_settings["enabled"] == true
          cursor = server.traffic_cursor
          unavailable = cursor["error"].present? || cursor["checked_at"].blank? || Time.iso8601(cursor["checked_at"]) < 2.minutes.ago
          transition(server, "traffic_unavailable", unavailable, "HTTP traffic collector unavailable", policy, now)
          # Evaluate only a complete minute and never use delayed replay to page
          # someone about a spike that happened long ago.
          bucket = server.http_traffic_buckets.find_by(bucket_at: now.beginning_of_minute - 1.minute, resolution: "minute")
          if bucket && !unavailable && cursor["backlog_bytes"].to_i.zero?
            total = bucket.data.values.reduce({}) { |sum, data| HttpTrafficCollector.merge(sum, data) }
            requests = total.fetch("requests", 0)
            error_rate = requests >= 20 ? total.fetch("statuses", {}).fetch("5xx", 0) * 100.0 / requests : 0
            { "http_error_percent" => [ error_rate, "HTTP 5xx error rate" ], "requests_per_minute" => [ requests, "HTTP request rate" ], "suspicious_per_minute" => [ total.fetch("suspicious", 0), "Suspicious HTTP request patterns" ] }.each do |signal, (value, label)|
              threshold = policy.fetch(signal)
              transition(server, signal, threshold.positive? && value >= threshold, "#{label} exceeds #{threshold}#{signal == 'http_error_percent' ? '%' : '/min'}", policy, now)
            end
          end
        end
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{key})")
      end
    end
  end

  def self.transition(server, signal, breached, message, policy, now)
    server.with_lock do
      transition_locked(server, signal, breached, message, policy, now)
    end
  end

  def self.transition_locked(server, signal, breached, message, policy, now)
    incident = server.monitoring_incidents.find_by(signal: signal, resolved_at: nil)
    if breached
      incident ||= server.monitoring_incidents.create!(signal: signal, message: message, started_at: now, last_seen_at: now)
      # A missing interval restarts the sustained window; don't join observations
      # separated by an outage of the monitoring worker.
      started = incident.last_seen_at < now - 90.seconds && incident.state == "pending" ? now : incident.started_at
      firing = now - started >= policy.fetch("window_minutes").minutes
      first_fire = firing && incident.state == "pending"
      incident.update!(last_seen_at: now, started_at: started, state: firing ? "firing" : incident.state)
      enqueue(incident, policy) if first_fire
    elsif incident
      was_firing = incident.state == "firing"
      incident.update!(resolved_at: now, last_seen_at: now, state: was_firing ? "resolved" : "discarded", message: "Recovered: #{message}")
      enqueue(incident, policy) if was_firing
    end
  end

  def self.enqueue(incident, policy)
    incident.update!(delivery_status: policy["email"] ? "queued" : "disabled")
    MonitoringNotificationJob.perform_later(incident.id, incident.state) if policy["email"]
  end
end
