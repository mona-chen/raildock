require "net/ssh"

class ServerTestService
  class MissingOrganizationKey < StandardError; end
  class NoOrganization < StandardError; end

  def initialize(organization:, host:, ssh_user: nil, host_key: nil)
    @organization = organization
    @host = host.to_s.strip
    @ssh_user = ssh_user.presence || DokkuEngineConstants::SSH_USER
    @host_key = host_key
  end

  def test
    raise NoOrganization, "Organization is required" unless @organization
    return error("Host is required") if @host.blank?

    org_key = @organization.ensure_ssh_key!
    return error("Organization SSH key is missing") if org_key.blank? || org_key.private_key.blank?

    server = build_temp_server(org_key.private_key)
    result = DokkuEngine.new(server).validate_connection

    if result[:success]
      # The dokku user cannot run raw shell commands, so detect OS/uptime via
      # the root user. Best-effort: missing root access falls back to defaults.
      host_info = begin
        HostEngine.new(server).host_info
      rescue => e
        Rails.logger.warn "Server test: host info unavailable for #{@host}: #{e.message}"
        { os: "Unknown", uptime: "unknown" }
      end

      logs = [
        "Connected to #{server.host} as #{server.ssh_user}",
        "Host key fingerprint: #{server.host_key_fingerprint}",
        "OS: #{host_info[:os]}",
        "Uptime: #{host_info[:uptime]}",
        "Docker: #{result[:docker_version]}",
        "Dokku: #{result[:dokku_version]}"
      ]
      logs << "Public IP: #{result[:public_ip]}" if result[:public_ip].present?

      {
        success: true,
        host: server.host,
        ssh_user: server.ssh_user,
        host_key: server.host_key,
        host_key_fingerprint: server.host_key_fingerprint,
        dokku_version: result[:dokku_version],
        docker_version: result[:docker_version],
        os: host_info[:os],
        uptime: host_info[:uptime],
        public_ip: result[:public_ip],
        logs: logs
      }
    else
      error(result[:output] || "Connection test failed")
    end
  rescue Net::SSH::AuthenticationFailed => e
    error("SSH authentication failed: #{e.message}")
  rescue Net::SSH::HostKeyMismatch => e
    error("Host key mismatch: #{e.message}")
  rescue Net::SSH::Exception => e
    error("SSH error: #{e.message}")
  rescue => e
    Rails.logger.error "Server test failed for #{@host}: #{e.message}"
    error("Connection test failed: #{e.message}")
  end

  private

  def build_temp_server(private_key)
    server = Server.new(
      organization: @organization,
      host: @host,
      ssh_user: @ssh_user,
      status: :disconnected
    )
    server.ssh_key = private_key
    server.host_key = @host_key if @host_key.present?
    server
  end

  def error(message)
    { success: false, error: message, logs: [ message ] }
  end
end
