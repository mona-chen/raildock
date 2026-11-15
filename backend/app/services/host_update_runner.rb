require "base64"
require "open3"
require "shellwords"

# Schedules a detached host operation. It never replaces its own container.
class HostUpdateRunner
  ACTIVE = %w[scheduled pulling backing_up restarting verifying rolling_back].freeze
  STATES = (ACTIVE + %w[completed rolled_back failed busy unavailable]).freeze

  def initialize(server: nil)
    @server = server
    @directory = ENV["RAILDOCK_INSTALL_DIR"].presence || "/opt/raildock"
  end

  def schedule(version)
    return { success: false, error: "Invalid update image version" } unless version.match?(/\A(?:edge|\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?)\z/)

    expected_container = @server ? ENV["HOSTNAME"].to_s : nil
    if @server && !expected_container.match?(/\A[a-f0-9]{12,64}\z/)
      return { success: false, error: "Cannot verify this container's identity on the update host. Use the installation host CLI." }
    end
    identity_check = if expected_container
      "container=$(docker compose -f #{Shellwords.escape(File.join(@directory, 'docker-compose.yml'))} ps -q raildock); case \"$container\" in #{expected_container}*) ;; *) exit 1 ;; esac"
    else
      "true"
    end
    id = SecureRandom.hex(16)
    script = Base64.strict_encode64(File.binread(Rails.root.join("lib/raildock/host_update.sh")))
    dir = Shellwords.escape(@directory)
    path = Shellwords.escape(File.join(@directory, "data/updates", "#{id}.sh"))
    command = <<~SH
      set -eu
      for tool in systemd-run docker flock timeout sha256sum; do command -v "$tool" >/dev/null; done
      test -d /run/systemd/system
      test -f #{dir}/docker-compose.yml
      test -f #{dir}/.env
      cd #{dir}
      #{identity_check}
      test ! -L #{dir}/data
      test ! -L #{dir}/data/updates
      install -d -m 700 #{dir}/data/updates
      printf '%s' '#{script}' | base64 -d > #{path}
      chmod 700 #{path}
      systemd-run --unit=raildock-update-#{id} --collect --property=Type=exec /bin/bash #{path} #{dir} #{Shellwords.escape(version)} #{id}
      printf 'raildock_update_scheduled\n'
    SH
    result = run(command)
    return { success: false, error: "Could not schedule the host updater. Verify the local SSH target, installation directory and systemd; the app was not stopped." } unless result[:success] && result[:output].to_s.lines.map(&:strip).include?("raildock_update_scheduled")

    SystemSetting.set!("update_operation_id", id)
    SystemSetting.set!("update_operation_server_id", @server&.id.to_s)
    SystemSetting.set!("update_operation_version", version)
    { success: true, operation_id: id, message: "Update scheduled on the host. RailDock will briefly disconnect while the new image starts." }
  end

  def status(id)
    return nil unless id.to_s.match?(/\A[a-f0-9]{32}\z/)

    path = Shellwords.escape(File.join(@directory, "data/updates", id, "status.json"))
    result = run("cat #{path}")
    return { "status" => "scheduled" } unless result[:success]

    data = JSON.parse(result[:output])
    return { "status" => "unavailable" } unless STATES.include?(data["status"])

    data.slice("id", "status", "version")
  rescue JSON::ParserError
    { "status" => "unavailable" }
  end

  private

  def run(command)
    return HostEngine.new(@server).run(command) if @server

    output, status = Open3.capture2e("/bin/bash", "-c", command)
    { success: status.success?, output: output }
  end
end
