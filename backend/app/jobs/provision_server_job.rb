require "net/ssh"
require "base64"
require "digest"
require "shellwords"

class ProvisionServerJob < ApplicationJob
  # Bootstrapping a host installs Docker, Dokku and plugins and can take many
  # minutes. Keep it off the control-plane worker so it cannot hold a thread
  # deployments need, and off `backups` so it cannot delay WAL archiving.
  queue_as :maintenance

  def perform(setup_id, organization_id, host, admin_user, base_url, proxy_mode: "managed", server_name: nil, base_domain: nil, auto_domains: true,
              external_proxy_network: nil, external_proxy_http_entrypoint: nil, external_proxy_https_entrypoint: nil,
              external_proxy_cert_resolver: nil, external_proxy_redirect_middleware: nil)
    organization = Organization.find(organization_id)
    org_key = organization.ensure_ssh_key!

    if org_key.blank? || org_key.private_key.blank?
      broadcast(setup_id, type: "failed", error: "Organization SSH key is missing")
      return
    end

    public_key = org_key.public_key
    private_key = org_key.private_key
    proxy_mode = proxy_mode.to_s.presence || "managed"

    unless Server::PROXY_MODES.include?(proxy_mode)
      broadcast(setup_id, type: "failed", error: "Unknown proxy mode #{proxy_mode.inspect}")
      return
    end

    # Checked again here (the API checks first) because a second wizard run
    # could have connected the same host while this job was queued. Failing
    # now avoids re-running the whole bootstrap only to hit the uniqueness
    # validation at the end.
    if (existing = Server.where(organization_id: organization.id).where("LOWER(host) = ?", host.to_s.downcase).first)
      broadcast(setup_id, type: "failed", error: "#{host} is already connected as \"#{existing.name}\". Remove that server first or validate its connection instead.")
      return
    end

    if proxy_mode == "external" && external_proxy_network.blank?
      broadcast(setup_id, type: "failed", error: "External proxy mode requires EXTERNAL_PROXY_NETWORK")
      return
    end

    broadcast(setup_id, type: "log", line: "Starting automated provisioning for #{host} (PROXY_MODE=#{proxy_mode})")

    admin_server = build_admin_server(host, admin_user, private_key)
    builder = SshConnectionBuilder.new(admin_server, user: admin_user)

    begin
      Net::SSH.start(host, admin_user, builder.options) do |ssh|
        broadcast(setup_id, type: "log", line: "Connected to #{host} as #{admin_user}")
        run_remote_bootstrap(ssh, setup_id, base_url, public_key, proxy_mode, external_proxy_network: external_proxy_network)
        host_keys = read_host_keys(ssh)
        if host_keys.present?
          admin_server.host_key = host_keys
          admin_server.host_key_fingerprint = host_key_fingerprints(host_keys).join(", ")
          broadcast(setup_id, type: "log", line: "Captured #{host_keys.lines.count} host key(s)")
        end
      end
    ensure
      builder.cleanup
    end

    broadcast(setup_id, type: "log", line: "Bootstrap complete. Validating Dokku connection...")

    result = ServerTestService.new(organization: organization, host: host, ssh_user: "dokku", host_key: admin_server.host_key).test
    unless result[:success]
      broadcast(setup_id, type: "failed", error: result[:error] || "Dokku validation failed")
      return
    end

    Array(result[:logs]).each { |line| broadcast(setup_id, type: "log", line: line) }

    server = Server.create!(
      organization: organization,
      name: server_name.presence || "RailDock #{host}",
      host: host,
      ssh_user: "dokku",
      ssh_key: private_key,
      status: :connected,
      host_key: result[:host_key] || admin_server.host_key,
      host_key_fingerprint: result[:host_key_fingerprint].presence || admin_server.host_key_fingerprint,
      dokku_version: result[:dokku_version],
      docker_version: result[:docker_version],
      os: result[:os],
      uptime: result[:uptime],
      public_ip: result[:public_ip],
      base_domain: base_domain,
      auto_domains: auto_domains,
      default_proxy: "traefik",
      proxy_mode: proxy_mode,
      external_proxy_network: external_proxy_network,
      external_proxy_http_entrypoint: external_proxy_http_entrypoint,
      external_proxy_https_entrypoint: external_proxy_https_entrypoint,
      external_proxy_cert_resolver: external_proxy_cert_resolver,
      external_proxy_redirect_middleware: external_proxy_redirect_middleware
    )

    broadcast(setup_id, type: "completed", server_id: server.id, host: server.host, host_key_fingerprint: server.host_key_fingerprint)
  rescue ActiveRecord::RecordNotFound
    broadcast(setup_id, type: "failed", error: "Organization not found")
  rescue => e
    Rails.logger.error "ProvisionServerJob failed for #{host}: #{e.class}: #{e.message}"
    broadcast(setup_id, type: "failed", error: "Provisioning failed: #{e.message}")
  end

  private

  def build_admin_server(host, admin_user, private_key)
    server = Server.new(host: host, ssh_user: admin_user, status: :disconnected)
    server.ssh_key = private_key
    server
  end

  def read_host_keys(ssh)
    output = +""
    exit_status = nil
    ssh.open_channel do |channel|
      channel.exec("cat /etc/ssh/ssh_host_*_key.pub") do |_, success|
        return unless success

        channel.on_data { |_, data| output << data }
        channel.on_extended_data { |_, _, data| output << data }
        channel.on_request("exit-status") { |_, data| exit_status = data.read_long }
      end
    end
    ssh.loop

    exit_status == 0 && output.present? ? output : nil
  end

  def host_key_fingerprints(host_keys)
    host_keys.to_s.each_line.filter_map { |line| fingerprint_for_host_key_line(line) }
  end

  def fingerprint_for_host_key_line(line)
    match = line.to_s.match(/(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2-\S+)\s+(\S+)/)
    return nil unless match

    blob = match[2]
    "SHA256:" + Base64.strict_encode64(Digest::SHA256.digest(Base64.decode64(blob))).delete("=")
  rescue
    nil
  end

  def run_remote_bootstrap(ssh, setup_id, base_url, public_key, proxy_mode, external_proxy_network: nil)
    command = self.class.bootstrap_command(base_url, public_key, proxy_mode, external_proxy_network: external_proxy_network)

    broadcast(setup_id, type: "log", line: "$ #{command}")

    exit_status = nil
    ssh.open_channel do |channel|
      channel.exec(command) do |_, success|
        unless success
          broadcast(setup_id, type: "failed", error: "Failed to execute bootstrap on remote host")
          return
        end

        channel.on_data do |_, data|
          data.each_line { |line| broadcast(setup_id, type: "log", line: line.chomp) }
        end

        channel.on_extended_data do |_, _type, data|
          data.each_line { |line| broadcast(setup_id, type: "log", line: line.chomp, stream: "stderr") }
        end

        channel.on_request("exit-status") do |_, data|
          exit_status = data.read_long
        end
      end
    end
    ssh.loop

    if exit_status != 0
      broadcast(setup_id, type: "failed", error: "Bootstrap exited with status #{exit_status}")
      raise "Bootstrap failed"
    end
  end

  # Every interpolated value is shell-escaped: the proxy network and base URL
  # are user-supplied and this string runs on the remote host. bootstrap.sh
  # must run as root, so a non-root admin user goes through `sudo -n` (which
  # fails immediately instead of hanging on a password prompt).
  def self.bootstrap_command(base_url, public_key, proxy_mode, external_proxy_network: nil)
    raise ArgumentError, "unknown proxy mode #{proxy_mode.inspect}" unless Server::PROXY_MODES.include?(proxy_mode.to_s)

    script_url = "#{base_url.to_s.chomp('/')}/bootstrap.sh"
    env = [ "PROXY_MODE=#{Shellwords.escape(proxy_mode.to_s)}" ]
    env << "EXTERNAL_PROXY_NETWORK=#{Shellwords.escape(external_proxy_network.to_s)}" if external_proxy_network.present?

    "if [ \"$(id -u)\" -eq 0 ]; then RD_SUDO=''; else RD_SUDO='sudo -n'; fi; " \
      "curl -fsSL #{Shellwords.escape(script_url)} | $RD_SUDO env #{env.join(' ')} bash -s -- #{Shellwords.escape(public_key.to_s.strip)}"
  end

  def broadcast(setup_id, payload)
    sanitized = payload.transform_values do |value|
      value.is_a?(String) ? value.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�") : value
    end
    ActionCable.server.broadcast("server_setup:#{setup_id}", sanitized)
    SetupProgress.update(setup_id, sanitized)
  end
end
