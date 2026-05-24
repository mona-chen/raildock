require "net/ssh"
require "shellwords"

# Runs raw shell/Docker commands on the host server as root.
# Unlike DokkuEngine (which connects as the restricted dokku user),
# HostEngine connects as root and can run docker, iptables, etc.
class HostEngine
  SSH_TIMEOUT = 30
  SSH_CONNECTION_TIMEOUT = 10
  SSH_USER = "root"

  attr_reader :server

  def initialize(server)
    @server = server
  end

  # Run a command on the host as root.
  # Returns { success: bool, output: string }
  def run(command)
    return { success: false, output: "No SSH key configured" } if server.ssh_key.blank?

    output = ""
    exit_code = nil

    Net::SSH.start(
      server.public_ip || server.host,
      SSH_USER,
      key_data: [server.ssh_key],
      non_interactive: true,
      timeout: SSH_TIMEOUT,
      verify_host_key: :never,
      host_key_alias: "#{server.host}-root"
    ) do |ssh|
      channel = ssh.open_channel do |ch|
        ch.exec(command) do |_, success|
          unless success
            return { success: false, output: "Failed to execute command" }
          end

          ch.on_data { |_, data| output += data }
          ch.on_extended_data { |_, type, data| output += data }
          ch.on_request("exit-status") { |_, data| exit_code = data.read_long }
        end
      end
      channel.wait
    end

    { success: exit_code == 0, output: output }
  rescue Net::SSH::AuthenticationFailed => e
    { success: false, output: "Authentication failed: #{e.message}" }
  rescue Net::SSH::ConnectionTimeout
    { success: false, output: "SSH connection timed out" }
  rescue => e
    { success: false, output: "SSH error: #{e.message}" }
  end

  # ── Docker helpers ──────────────────────────

  def docker_network_create(name, driver: "bridge")
    run("docker network create #{name} --driver #{driver} 2>/dev/null || true")
  end

  def docker_network_connect(container, network, aliases: [])
    alias_flags = aliases.map { |a| "--alias #{Shellwords.escape(a)}" }.join(" ")
    run("docker network connect #{alias_flags} #{Shellwords.escape(network)} #{Shellwords.escape(container)} 2>/dev/null || true")
  end

  def docker_network_disconnect(container, network)
    run("docker network disconnect #{Shellwords.escape(network)} #{Shellwords.escape(container)} 2>/dev/null || true")
  end

  def docker_network_inspect(network)
    run("docker network inspect #{Shellwords.escape(network)} --format '{{json .Containers}}'")
  end

  def docker_inspect(container, format: nil)
    fmt = format ? "--format='#{format}' " : ""
    run("docker inspect #{fmt}#{Shellwords.escape(container)}")
  end

  def docker_ps
    run("docker ps --format '{{.Names}}'")
  end

  # ── Dokku container helpers ─────────────────

  # Dokku web containers are named <app>.web.1
  def dokku_container_name(app_name)
    "#{app_name}.web.1"
  end
end
