require "base64"
require "shellwords"

class ServerPackageManager
  ACTIVE = %w[scheduled running].freeze
  class Busy < StandardError; end
  class InvalidPlan < StandardError; end

  def self.start(server, kind, reviewed_id: nil)
    raise ArgumentError unless %w[inspect check install].include?(kind)
    server.with_lock do
      state = server.package_updates
      raise Busy, "Server maintenance is already in progress" if ACTIVE.include?(state.dig("operation", "status"))
      if kind == "install"
        unless reviewed_id.to_s.match?(/\A[a-f0-9]{32}\z/) && state.dig("operation", "id") == reviewed_id && state["checked_at"].present? && Time.iso8601(state["checked_at"]) > 1.hour.ago && state["count"].to_i.positive? && state["status"] == "completed"
          raise InvalidPlan, "Check and review package updates before installing"
        end
      end
      operation = { "id" => SecureRandom.hex(16), "kind" => kind, "status" => "scheduled", "started_at" => Time.current.iso8601, "reviewed_id" => reviewed_id }
      server.update!(package_updates: state.except("error", "log_tail").merge("operation" => operation))
    end
    ServerPackageUpdateJob.perform_later(server.id, "start", server.package_updates.dig("operation", "id"))
    server.package_updates
  rescue ActiveJob::EnqueueError
    fail_operation(server, "The maintenance worker could not be scheduled. Try again.")
    raise
  end

  def self.schedule(server, id)
    operation = server.reload.package_updates["operation"]
    return unless operation && operation["id"] == id && operation["status"] == "scheduled"
    script = Base64.strict_encode64(File.binread(Rails.root.join("lib/raildock/server_packages.py")))
    command = <<~SH
      set -eu
      . /etc/os-release
      case "$ID" in ubuntu|debian) ;; *) echo raildock_packages_unsupported; exit 0 ;; esac
      command -v python3 >/dev/null
      command -v systemd-run >/dev/null
      test -d /run/systemd/system
      test ! -L /var/lib/raildock
      test ! -L /var/lib/raildock/maintenance
      install -d -m 700 /var/lib/raildock/maintenance
      test ! -L /var/lib/raildock/maintenance/#{id}
      install -d -m 700 /var/lib/raildock/maintenance/#{id}
      printf '%s' '#{script}' | base64 -d > /var/lib/raildock/maintenance/#{id}/run.py
      echo raildock_maintenance_preflight_ready
      systemd-run --collect --unit=raildock-packages-#{id} --property=Type=exec --property=Nice=10 --property=IOSchedulingClass=best-effort --property=IOSchedulingPriority=7 /usr/bin/python3 /var/lib/raildock/maintenance/#{id}/run.py #{id} #{Shellwords.escape(operation.fetch("kind"))} #{Shellwords.escape(operation["reviewed_id"].to_s)}
      echo raildock_maintenance_started
    SH
    result = HostEngine.new(server).run(command)
    if result[:success] && result[:output].to_s.lines.map(&:strip).include?("raildock_packages_unsupported")
      state = { "supported" => false, "status" => "completed", "checked_at" => Time.current.iso8601, "count" => 0, "packages" => [], "release" => { "supported" => false, "available" => false }, "message" => "Package management is available for Ubuntu and Debian hosts. Use your distribution’s package manager from its console.", "operation" => operation.merge("status" => "completed") }
      return Server.where(id: server.id).update_all(package_updates: state)
    end
    unless result[:success] && result[:output].to_s.lines.map(&:strip).include?("raildock_maintenance_started")
      uncertain = result[:output].to_s.lines.map(&:strip).include?("raildock_maintenance_preflight_ready")
      fail_operation(server, uncertain ? "Could not confirm host maintenance startup. It may be running; inspect the host before retrying." : "Host maintenance preflight failed. Requires root SSH, Python 3 and systemd; no package changes were started by RailDock.", status: uncertain ? "running" : "failed")
      ServerPackageUpdateJob.set(wait: 10.seconds).perform_later(server.id, "poll", id) if uncertain
      return
    end
    Server.where(id: server.id).update_all(package_updates: server.reload.package_updates.merge("operation" => operation.merge("status" => "running")))
    ServerPackageUpdateJob.set(wait: 5.seconds).perform_later(server.id, "poll", id)
  end

  def self.poll(server, id)
    operation = server.package_updates["operation"]
    return unless operation && operation["id"] == id && ACTIVE.include?(operation["status"])
    # The host owns execution, so an API/worker restart cannot cancel apt/dpkg.
    result = HostEngine.new(server).run("test ! -L /var/lib/raildock/maintenance/#{id}/status.json && head -c 262144 /var/lib/raildock/maintenance/#{id}/status.json")
    if result[:success]
      data = JSON.parse(result[:output])
      raise InvalidPlan unless data["id"] == id && %w[running completed failed].include?(data["status"])
      data["log_tail"] = LogRedactor.redact(data["log_tail"].to_s).last(12000)
      state = server.package_updates.except("error").merge(data.except("id", "kind", "started_at", "updated_at"), "operation" => operation.merge(data.slice("status", "phase", "updated_at")))
      Server.where(id: server.id).update_all(package_updates: state)
      if data["status"] == "completed" && data["os"].present?
        Server.where(id: server.id).update_all(os: data["os"].truncate(200))
      end
      return unless data["status"] == "running"
    end
    # Do not claim a timed-out operation stopped: it may still be running on the
    # host. Keep the operation blocked, but keep reconciling slowly so a host
    # that comes back after an outage can report completion. Never rerun apt.
    if Time.iso8601(operation.fetch("started_at")) < 4.hours.ago
      state = server.package_updates.merge("error" => "Host maintenance has not reported completion. RailDock will keep checking; inspect systemctl status raildock-packages-#{id} on the host before starting another operation.")
      Server.where(id: server.id).update_all(package_updates: state)
      return ServerPackageUpdateJob.set(wait: 5.minutes).perform_later(server.id, "poll", id)
    end
    ServerPackageUpdateJob.set(wait: 10.seconds).perform_later(server.id, "poll", id)
  rescue JSON::ParserError
    fail_operation(server, "The host returned invalid maintenance status. Inspect the host before retrying.", status: "running")
  end

  def self.fail_operation(server, message, status: "failed")
    state = server.reload.package_updates
    Server.where(id: server.id).update_all(package_updates: state.merge("error" => message, "operation" => state.fetch("operation", {}).merge("status" => status)))
  end
end
