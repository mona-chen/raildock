require "base64"
require "shellwords"

class NetworkFlowCollector
  DEFAULTS = { "enabled" => false, "retention_days" => 0 }.freeze

  def self.settings(server) = DEFAULTS.merge(server.network_flow_settings)

  def self.call(server)
    return unless settings(server)["enabled"]
    ApplicationRecord.connection_pool.with_connection do |connection|
      key = "hashtextextended('raildock:network-flow:#{Integer(server.id)}', 0)"
      return unless connection.select_value("SELECT pg_try_advisory_lock(#{key})")
      begin
        server.reload
        return unless settings(server)["enabled"]
        at = server.network_flow_snapshot["sampled_at"]
        return if at && Time.iso8601(at) > 9.seconds.ago
        services = Service.joins(:project).where(projects: { server_id: server.id }).to_a
        ids = services.map(&:id)
        links = ServiceLink.where(from_service_id: ids, to_service_id: ids).to_a
        if links.empty?
          server.update_columns(network_flow_snapshot: { "sampled_at" => Time.current.iso8601, "links" => [] })
          return
        end
        linked_ids = links.flat_map { |link| [ link.from_service_id, link.to_service_id ] }.to_set
        services.select! { |service| linked_ids.include?(service.id) }
        plugins = ServiceSubtype.where.not(dokku_plugin: nil).distinct.pluck(:dokku_plugin)
        config = { epoch: settings(server)["epoch"], scope: Digest::SHA256.hexdigest("#{Rails.application.secret_key_base}:#{server.id}")[0, 16], services: services.to_h { |s| [ s.id.to_s, [ s.dokku_app_name, *plugins.map { |p| "dokku.#{p}.#{s.dokku_app_name}" } ].compact ] }, links: links.map { |l| { id: l.id.to_s, from: l.from_service_id.to_s, to: l.to_service_id.to_s } } }
        script = Base64.strict_encode64(File.binread(Rails.root.join("lib/raildock/network_flows.py")))
        argument = Base64.strict_encode64(config.to_json)
        raise ArgumentError, "Flow mapping budget exceeded" if argument.bytesize > 64_000
        result = HostEngine.new(server).run("timeout 15 python3 -c #{Shellwords.escape("import base64;exec(base64.b64decode('#{script}'))")} #{Shellwords.escape(argument)}")
        data = result[:success] ? JSON.parse(result[:output]) : nil
        unless data.is_a?(Hash) && data["links"].is_a?(Array) && data["sampled_at"].present?
          server.update_columns(network_flow_snapshot: { "sampled_at" => Time.current.iso8601, "error" => "TCP flow collection unavailable. Check Linux, root SSH, Python 3, nsenter and ss." })
          return
        end
        # Do not re-enable or save a sample after a concurrent settings change.
        server.with_lock do
          return unless settings(server)["enabled"] && settings(server)["epoch"] == config[:epoch]
          prior = Array(server.network_flow_snapshot["links"]).index_by { |row| row["id"] }
          data["links"].each do |row|
            row["last_activity_at"] = row["sent_bytes"].to_i.positive? || row["received_bytes"].to_i.positive? ? data["sampled_at"] : prior.dig(row["id"], "last_activity_at")
          end
          server.update!(network_flow_snapshot: data)
          if settings(server)["retention_days"].positive?
            data["links"].each do |row|
              next unless row["state"] == "sampled" && links.any? { |link| link.id.to_s == row["id"] }
              sample = NetworkFlowSample.find_or_initialize_by(server: server, service_link_id: row["id"], sampled_at: Time.iso8601(data["sampled_at"]).beginning_of_minute)
              sample.sent_bytes = sample.sent_bytes.to_i + row["sent_bytes"].to_i
              sample.received_bytes = sample.received_bytes.to_i + row["received_bytes"].to_i
              sample.connections = row["connections"]
              sample.window_seconds = sample.window_seconds.to_f + row["window_seconds"].to_f
              sample.save!
            end
          end
        end
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{key})")
      end
    end
  rescue ApplicationController::AuthorizationDenied, ServiceOperationLock::Busy
    raise
  rescue => e
    Rails.logger.warn "Network flow collection failed for #{server.id}: #{e.class}"
    server.update_columns(network_flow_snapshot: { "sampled_at" => Time.current.iso8601, "error" => "TCP flow collection unavailable" })
  end

  def self.prune(server)
    days = settings(server)["retention_days"]
    rows = NetworkFlowSample.where(server: server)
    rows = rows.where("sampled_at < ?", days.days.ago) if days.positive?
    rows.in_batches.delete_all
  end
end
