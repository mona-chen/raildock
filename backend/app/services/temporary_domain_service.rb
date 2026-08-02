# frozen_string_literal: true

# Auto-provisions a temporary public domain for an app service when the
# project's server has a base_domain configured and auto_domains enabled.
#
# For magic DNS services (sslip.io, nip.io, traefik.me) the hostname embeds
# the server's public IP and no SSL is requested. For regular domains, a
# letsencrypt-backed subdomain is generated.
#
# This is used by one-click template deploys, manifest apply, and manual
# service creation so web services are reachable immediately without forcing
# the user to add a domain by hand.
class TemporaryDomainService
  def initialize(server)
    @server = server
  end

  # Ensures the service has one temporary domain. Returns the domain or nil.
  def ensure_for(service, engine: nil)
    return nil unless @server
    return nil unless @server.auto_domains?

    if @server.base_domain.blank?
      ActivityEvent.create!(
        project: service.project,
        service_name: service.name,
        action: :warning,
        message: "Auto-domains is enabled but the server has no base domain. Set one in Settings → Server to get temporary domains."
      )
      return nil
    end

    return nil unless service.service_type_app?
    return nil if service.domains.any?
    return nil if service.config&.dig("proxy", "enabled") == false

    hostname = @server.temporary_hostname(service.dokku_app_name)
    return nil unless hostname

    use_ssl = !@server.magic_domain?
    target_port = service.config&.dig("proxy", "ports")&.first&.dig("container") || service.effective_port

    domain = service.domains.create!(
      hostname: hostname,
      port: use_ssl ? 443 : 80,
      target_port: target_port,
      ssl: use_ssl,
      letsencrypt: use_ssl,
      temporary: true,
      ssl_status: use_ssl ? "pending" : "none",
      challenge_type: "http"
    )

    if engine && @server.ssh_key.present?
      engine.domain_add(service.dokku_app_name, hostname)
      # Temporary magic (sslip.io) domains never get TLS certs — always HTTP-only.
      engine.sync_port_mappings(service.dokku_app_name, target_port, https: false)
    end

    domain
  rescue => e
    Rails.logger.warn "Failed to create temporary domain for #{service.dokku_app_name}: #{e.message}"
    nil
  end
end
