require "tempfile"
require "base64"
require "digest"

class SshConnectionBuilder
  LOCAL_HOST_ALIASES = %w[localhost 127.0.0.1 ::1 host.docker.internal].freeze
  SSH_TIMEOUT = 30

  attr_reader :server, :user

  def initialize(server, user:)
    @server = server
    @user = user
  end

  def options
    base = {
      key_data: [ server.ssh_key ].compact,
      keys_only: true,
      use_agent: false,
      non_interactive: true,
      timeout: SSH_TIMEOUT,
      keepalive: true,
      keepalive_interval: 15,
      keepalive_maxcount: 3
    }

    if server.host_key.present?
      base[:verify_host_key] = :secure
      base[:user_known_hosts_file] = known_hosts_file.path
    else
      base[:verify_host_key] = :accept_new_or_local_tunnel
    end

    base[:host_key_alias] = host_alias if user == "root"

    base
  end

  def capture_host_key!(session)
    return if server.host_key.present?

    transport = session.respond_to?(:transport) ? session.transport : session
    key = transport.host_keys.first
    return unless key

    server.update!(
      host_key: key.ssh_type + " " + [ key.to_blob ].pack("m0"),
      host_key_fingerprint: fingerprint_for(key)
    )
  end

  def cleanup
    @known_hosts_file&.close!
  end

  private

  def known_hosts_file
    @known_hosts_file ||= begin
      f = Tempfile.new([ "known_hosts_#{server.id}", "" ])
      f.write("#{server.host} #{server.host_key}\n")
      f.flush
      f
    end
  end

  def host_alias
    "#{server.host}-#{user}"
  end

  def fingerprint_for(key)
    "SHA256:" + Base64.strict_encode64(Digest::SHA256.digest(key.to_blob))
  end

  def local_host?
    LOCAL_HOST_ALIASES.include?(server.host.to_s.downcase)
  end
end
