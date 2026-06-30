require "net/ssh"
require "base64"
require "digest"

class ProvisionServerJob < ApplicationJob
  queue_as :default

  def perform(setup_id, organization_id, host, admin_user, base_url, proxy_mode: "managed", server_name: nil, base_domain: nil, auto_domains: true)
    organization = Organization.find(organization_id)
    org_key = organization.ensure_ssh_key!

    if org_key.blank? || org_key.private_key.blank?
      broadcast(setup_id, type: "failed", error: "Organization SSH key is missing")
      return
    end

    public_key = org_key.public_key
    private_key = org_key.private_key
    proxy_mode = proxy_mode.to_s.presence || "managed"

    broadcast(setup_id, type: "log", line: "Starting automated provisioning for #{host} (PROXY_MODE=#{proxy_mode})")

    admin_server = build_admin_server(host, admin_user, private_key)
    builder = SshConnectionBuilder.new(admin_server, user: admin_user)

    begin
      Net::SSH.start(host, admin_user, builder.options) do |ssh|
        broadcast(setup_id, type: "log", line: "Connected to #{host} as #{admin_user}")
        run_remote_bootstrap(ssh, setup_id, base_url, public_key, proxy_mode)
        host_keys = read_host_keys(ssh)
        if host_keys.present?
          admin_server.host_key = host_keys
          admin_server.host_key_fingerprint = fingerprint_for_host_key_line(host_keys.lines.first)
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
      host_key: result[:host_key],
      host_key_fingerprint: result[:host_key_fingerprint],
      dokku_version: result[:dokku_version],
      docker_version: result[:docker_version],
      os: result[:os],
      uptime: result[:uptime],
      public_ip: result[:public_ip],
      base_domain: base_domain,
      auto_domains: auto_domains,
      default_proxy: "traefik",
      proxy_mode: proxy_mode
    )

    broadcast(setup_id, type: "completed", server_id: server.id, host: server.host)
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

  def fingerprint_for_host_key_line(line)
    match = line.to_s.match(/(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2-\S+)\s+(\S+)/)
    return nil unless match

    blob = match[2]
    "SHA256:" + Base64.strict_encode64(Digest::SHA256.digest(Base64.decode64(blob))).delete("=")
  rescue
    nil
  end

  def run_remote_bootstrap(ssh, setup_id, base_url, public_key, proxy_mode)
    script_url = "#{base_url.chomp('/')}/bootstrap.sh"
    escaped_key = public_key.gsub("'", "'\"'\"'")
    command = "curl -fsSL #{script_url} | PROXY_MODE='#{proxy_mode}' bash -s -- '#{escaped_key}'"

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

  def broadcast(setup_id, payload)
    sanitized = payload.transform_values do |value|
      value.is_a?(String) ? value.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�") : value
    end
    ActionCable.server.broadcast("server_setup:#{setup_id}", sanitized)
    SetupProgress.update(setup_id, sanitized)
  end
end
