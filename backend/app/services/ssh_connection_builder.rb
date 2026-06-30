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

    base[:verify_host_key] = HostKeyVerifier.new(server)
    base[:host_key_alias] = host_alias if user == "root"

    base
  end

  def capture_host_key!(session)
    # The verifier captures the key on the first connection, so this is only
    # kept as a fallback for callers that already use it.
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

  def host_alias
    "#{server.host}-#{user}"
  end

  def fingerprint_for(key)
    fingerprint_for_blob(key.to_blob)
  end

  def fingerprint_for_blob(blob)
    # Match Net::SSH's SHA256 fingerprint format: base64, no padding.
    "SHA256:" + Base64.strict_encode64(Digest::SHA256.digest(blob)).delete("=")
  end

  def local_host?
    LOCAL_HOST_ALIASES.include?(server.host.to_s.downcase)
  end

  # Verifies the remote host key against captured fingerprints when a key is
  # stored, or accepts and stores the key on the first connection. This avoids
  # Net::SSH :secure/:always deprecation warnings, key-type mismatches, and
  # accidentally trusting a stale key from the container's known_hosts files.
  class HostKeyVerifier
    def initialize(server)
      @server = server
      @stored_fingerprints = fingerprints_from(server.host_key)
    end

    def verify(arguments)
      key = arguments[:key]
      fingerprint = arguments[:fingerprint]

      if @stored_fingerprints.any?
        return true if @stored_fingerprints.include?(fingerprint)

        raise Net::SSH::HostKeyMismatch, "Host key #{fingerprint} does not match the stored key"
      end

      capture(key, fingerprint)
      true
    end

    def verify_signature(&block)
      yield
    end

    private

    def capture(key, fingerprint)
      existing = @server.host_key.to_s
      entry = "#{key.ssh_type} #{[ key.to_blob ].pack("m0")}"
      @server.host_key = existing.present? ? "#{existing}\n#{entry}" : entry
      @server.host_key_fingerprint ||= fingerprint
      @stored_fingerprints << fingerprint
    end

    def fingerprints_from(host_key)
      host_key.to_s.each_line.map do |line|
        _type, blob, = line.split(" ", 3)
        next if blob.blank?

        "SHA256:" + Base64.strict_encode64(Digest::SHA256.digest(Base64.decode64(blob))).delete("=")
      rescue
        nil
      end.compact
    end
  end
end
