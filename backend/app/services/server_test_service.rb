require "net/ssh"
require "tempfile"

class ServerTestService
  class MissingOrganizationKey < StandardError; end
  class NoOrganization < StandardError; end

  def initialize(organization:, host:, ssh_user: nil)
    @organization = organization
    @host = host.to_s.strip
    @ssh_user = ssh_user.presence || DokkuEngineConstants::SSH_USER
  end

  def test
    raise NoOrganization, "Organization is required" unless @organization
    return error("Host is required") if @host.blank?

    org_key = @organization.ensure_ssh_key!
    return error("Organization SSH key is missing") if org_key.blank? || org_key.private_key.blank?

    server = build_temp_server(org_key.private_key)
    builder = SshConnectionBuilder.new(server, user: server.ssh_user)

    session = Net::SSH.start(server.host, server.ssh_user, builder.options)
    capture_host_key!(server, session)
    session.close

    result = DokkuEngine.new(server).validate_connection

    if result[:success]
      logs = [
        "Connected to #{server.host} as #{server.ssh_user}",
        "Host key fingerprint: #{server.host_key_fingerprint}",
        "OS: #{result[:os]}",
        "Uptime: #{result[:uptime]}",
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
        os: result[:os],
        uptime: result[:uptime],
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
  ensure
    builder&.cleanup
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
    server
  end

  def capture_host_key!(server, session)
    key = session.host_keys.first
    return unless key

    server.host_key = key.ssh_type + " " + [ key.to_blob ].pack("m0")
    server.host_key_fingerprint = "SHA256:" + Base64.strict_encode64(Digest::SHA256.digest(key.to_blob))
  end

  def error(message)
    { success: false, error: message, logs: [message] }
  end
end
