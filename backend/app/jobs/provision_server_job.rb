require "net/ssh"

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
      end
    ensure
      builder.cleanup
    end

    broadcast(setup_id, type: "log", line: "Bootstrap complete. Validating Dokku connection...")

    result = ServerTestService.new(organization: organization, host: host, ssh_user: "dokku").test
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
    ActionCable.server.broadcast("server_setup:#{setup_id}", payload)
    SetupProgress.update(setup_id, payload)
  end
end
