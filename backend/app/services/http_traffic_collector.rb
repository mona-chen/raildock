require "base64"
require "shellwords"
require "zlib"

class HttpTrafficCollector
  def self.call(server)
    return unless server.traffic_settings["enabled"] == true

    ApplicationRecord.connection_pool.with_connection do |connection|
      key = "hashtextextended('raildock:http-traffic:#{Integer(server.id)}', 0)"
      return unless connection.select_value("SELECT pg_try_advisory_lock(#{key})")

      begin
        server.reload
        cursor = server.traffic_cursor
        return if cursor["checked_at"].present? && Time.iso8601(cursor["checked_at"]) > 10.seconds.ago

        domains = Domain.joins(service: :project).where(projects: { server_id: server.id }).order(:id).limit(5001).pluck(:hostname, :service_id).to_h
        raise ArgumentError, "Host domain budget exceeded" if domains.size > 5000

        config = server.traffic_settings.slice("path", "format", "capture_paths").merge(cursor: cursor.slice("inode", "offset"), domains: domains, top_n: 25)
        # An empty cursor really means first-enable; don't send an empty hash
        # with nil keys, which would accidentally replay the entire file.
        config[:cursor] = {} unless cursor["inode"].present?
        script = Base64.strict_encode64(File.binread(Rails.root.join("lib/raildock/http_traffic.py")))
        argument = Base64.strict_encode64(Zlib::Deflate.deflate(config.to_json))
        raise ArgumentError, "Host mapping budget exceeded" if argument.bytesize > 64_000

        result = HostEngine.new(server).run("timeout 15 python3 -c #{Shellwords.escape("import base64;exec(base64.b64decode('#{script}'))")} #{Shellwords.escape(argument)}")
        data = result[:success] ? JSON.parse(result[:output]) : nil
        unless data.is_a?(Hash) && data["cursor"].is_a?(Hash) && data["groups"].is_a?(Array)
          server.update_columns(traffic_cursor: cursor.merge("checked_at" => Time.current.iso8601, "error" => "Collection failed. Check Python 3, the log file and JSON format."))
          return
        end
        server.transaction do
          data["groups"].group_by { |group| group.fetch("at") }.each do |at, groups|
            [ [ "minute", Time.at(at).utc ], [ "hour", Time.at(at).utc.beginning_of_hour ] ].each do |resolution, time|
              bucket = server.http_traffic_buckets.find_or_initialize_by(bucket_at: time, resolution: resolution)
              merged = bucket.data.deep_dup
              groups.each do |group|
                service_id = group.fetch("service_id")
                merged[service_id] = merge(merged[service_id] || {}, group.except("at", "service_id"))
              end
              bucket.update!(data: merged)
            end
          end
          if data["backlog_bytes"].to_i.zero? && cursor["checked_at"].present? && Time.iso8601(cursor["checked_at"]) > 90.seconds.ago && cursor["error"].blank?
            [ Time.iso8601(cursor["checked_at"]).beginning_of_minute, Time.current.beginning_of_minute ].uniq.each do |minute|
              server.http_traffic_buckets.find_or_create_by!(bucket_at: minute, resolution: "minute") { |bucket| bucket.data = {} }
              server.http_traffic_buckets.find_or_create_by!(bucket_at: minute.beginning_of_hour, resolution: "hour") { |bucket| bucket.data = {} }
            end
          end
          server.update_columns(traffic_cursor: data.fetch("cursor").merge("checked_at" => Time.current.iso8601, "backlog_bytes" => data["backlog_bytes"], "rotated" => data["rotated"], "invalid_lines" => data["invalid_lines"], "rotations" => cursor.fetch("rotations", 0) + (data["rotated"] ? 1 : 0), "mapped_domains" => domains.size))
        end
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{key})")
      end
    end
  rescue ApplicationController::AuthorizationDenied, ServiceOperationLock::Busy
    raise
  rescue => e
    Rails.logger.warn "HTTP collection failed for server #{server.id}: #{e.class}"
    server.update_columns(traffic_cursor: server.traffic_cursor.merge("checked_at" => Time.current.iso8601, "error" => "Collection failed"))
  end

  def self.merge(left, right)
    result = %w[requests bandwidth suspicious].to_h { |key| [ key, left.fetch(key, 0) + right.fetch(key, 0) ] }
    result["histogram"] = (0..14).map { |i| Array(left["histogram"])[i].to_i + Array(right["histogram"])[i].to_i }
    result["statuses"] = left.fetch("statuses", {}).merge(right.fetch("statuses", {})) { |_key, a, b| a + b }
    paths = left.fetch("paths", {}).merge(right.fetch("paths", {})) { |_key, a, b| a + b }
    top = paths.except("(other paths)").sort_by { |_path, count| -count }.first(25).to_h
    overflow = paths.values.sum - top.values.sum
    top["(other paths)"] = overflow if overflow.positive?
    result["paths"] = top
    result
  end
end
