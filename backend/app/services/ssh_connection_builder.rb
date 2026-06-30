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

    base[:verify_host_key] = host_key_verifier
    base[:host_key_alias] = host_alias if user == "root"

    base
  end

  def capture_host_key!(session)
    return if server.host_key.present?

    transport = session.respond_to?(:transport) ? session.transport : session
    keys = Array(transport.host_keys).compact
    return if keys.empty?

    server.host_key = keys.map { |key| "#{key.ssh_type} #{[ key.to_blob ].pack("m0")}" }.join("\n")
    server.host_key_fingerprint = fingerprint_for(keys.first)
  end

  def cleanup
    @known_hosts_file&.close!
    @known_hosts_file = nil
  end

  private

  def host_key_verifier
    if server.host_key.present?
      StoredHostKeyVerifier.new(server)
    else
      :accept_new
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

  # Verifies the remote host against the key(s) captured when the server was
  # first provisioned. Using the stored fingerprint(s) directly avoids key-type
  # mismatches and the Net::SSH :secure/:always deprecation warnings.
  class StoredHostKeyVerifier
    def initialize(server)
      @fingerprints = fingerprints_from(server.host_key)
    end

    def verify(arguments)
      fp = arguments[:fingerprint]
      return true if @fingerprints.include?(fp)

      raise Net::SSH::HostKeyMismatch, "Host key #{fp} does not match the stored key"
    end

    def verify_signature(&block)
      yield
    end

    private

    def fingerprints_from(host_key)
      host_key.to_s.each_line.map do |line|
        type, blob, = line.split(" ", 3)
        next if type.blank? || blob.blank?

        key = Net::SSH::Buffer.new(Base64.decode64(blob)).read_key
        "SHA256:" + Base64.strict_encode64(Digest::SHA256.digest(key.to_blob))
      rescue
        nil
      end.compact
    end
  end
end
