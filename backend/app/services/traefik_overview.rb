require "json"

# Read-only view of the proxy that fronts a server's apps. It combines the
# host's Docker inventory with RailDock's intended routes and certificate
# state. It never edits Traefik configuration.
class TraefikOverview
  SAFE_REPORT_SETTINGS = {
    image: "image",
    letsencrypt_email: "letsencrypt-email",
    challenge_mode: "challenge-mode",
    dns_provider: "dns-provider",
    log_level: "log-level",
    api_enabled: "api-enabled",
    dashboard_enabled: "dashboard-enabled",
    http_entrypoint: "http-entry-point",
    https_entrypoint: "https-entry-point",
    api_vhost: "api-vhost",
    basic_auth_username: "basic-auth-username"
  }.freeze

  def initialize(server, host_engine: nil, engine: nil)
    @server = server
    @host_engine = host_engine || HostEngine.new(server)
    @engine = engine || DokkuEngine.new(server)
  end

  def call
    rows, inventory_error = container_rows
    running_names = rows.select { |row| row["State"].to_s == "running" }.map { |row| container_name(row) }.compact.to_set
    services = traefik_services

    routes = services.flat_map do |service|
      service.domains.map { |domain| route_for(service, domain, running_names, inventory_error) }
    end
    certificates = certificate_rows(services)

    {
      mode: server.proxy_mode,
      managed: !server.external_proxy?,
      network: server.external_proxy_network,
      entrypoints: {
        http: server.external_proxy_http_entrypoint,
        https: server.external_proxy_https_entrypoint
      },
      cert_resolver: server.external_proxy_cert_resolver,
      redirect_middleware: server.external_proxy_redirect_middleware,
      default_labels: server.external_proxy_default_labels || {},
      containers: proxy_containers(rows),
      settings: managed_settings,
      routes: routes,
      certificates: certificates,
      warnings: proxy_warnings,
      summary: {
        routes: routes.length,
        active_routes: routes.count { |route| route[:state] == "active" },
        routes_needing_attention: routes.count { |route| route[:state] != "active" },
        certificates: certificates.length,
        active_certificates: certificates.count { |certificate| certificate[:status] == "active" },
        certificates_needing_attention: certificates.count { |certificate| %w[pending failed].include?(certificate[:status]) },
        proxy_containers: proxy_containers(rows).length,
        running_proxy_containers: proxy_containers(rows).count { |container| container[:running] }
      },
      inventory_error: inventory_error,
      checked_at: Time.current.iso8601
    }
  end

  def proxy_containers(rows = nil)
    rows ||= container_rows.first
    rows.select do |row|
      row["Image"].to_s.downcase.include?("traefik") || row["Names"].to_s.downcase.include?("traefik")
    end.map { |row| normalize_container(row) }
  end

  private

  attr_reader :server, :host_engine, :engine

  def container_rows
    result = host_engine.docker_container_inventory
    return [ [], result[:output].presence || "Could not inspect Docker containers" ] unless result[:success]

    rows = result[:output].to_s.lines.filter_map do |line|
      stripped = line.strip
      JSON.parse(stripped) if stripped.present?
    rescue JSON::ParserError
      nil
    end
    [ rows, nil ]
  rescue => error
    Rails.logger.warn "Traefik overview inventory failed for server #{server.id}: #{error.message}"
    [ [], error.message ]
  end

  def app_services
    Service.where(project_id: server.project_ids, service_type: "app").includes(:project, :domains).order(:name).to_a
  end

  def traefik_services
    services = app_services
    return services if server.external_proxy?

    services.select { |service| service_proxy_type(service) == "traefik" }
  end

  def service_proxy_type(service)
    proxy = service.config&.dig("proxy") || {}
    (proxy["proxyType"] || proxy["type"] || server.default_proxy || "traefik").to_s
  end

  def route_for(service, domain, running_names, inventory_error)
    container = "#{service.dokku_app_name}.web.1"
    running = inventory_error ? nil : running_names.include?(container)
    state = route_state(service, domain, running)
    {
      id: "#{service.id}:#{domain.id}",
      service_id: service.id,
      service_name: service.name,
      project_id: service.project_id,
      project_name: service.project&.name,
      hostname: domain.hostname,
      rule: domain.traefik_rule,
      target_port: domain.resolved_target_port,
      backend: running ? "http://#{container}:#{domain.resolved_target_port}" : nil,
      container: container,
      running: running,
      proxy_enabled: service.config&.dig("proxy", "enabled") != false,
      temporary: domain.temporary?,
      wildcard: domain.wildcard?,
      ssl: domain.ssl,
      ssl_status: domain.ssl_status,
      ssl_expires_at: domain.ssl_expires_at&.iso8601,
      ssl_status_message: domain.ssl_status_message,
      state: state
    }
  end

  def route_state(service, domain, running)
    return "proxy_disabled" if service.config&.dig("proxy", "enabled") == false
    return "unknown" if running.nil?
    return "container_stopped" unless running
    return "certificate_failed" if domain.ssl && domain.ssl_status == "failed"
    return "certificate_pending" if domain.ssl && domain.ssl_status == "pending"

    "active"
  end

  def certificate_rows(services)
    services.flat_map do |service|
      service.domains.select(&:ssl).map do |domain|
        {
          id: domain.id,
          hostname: domain.hostname,
          service_id: service.id,
          service_name: service.name,
          project_name: service.project&.name,
          status: domain.ssl_status,
          expires_at: domain.ssl_expires_at&.iso8601,
          status_message: domain.ssl_status_message,
          challenge_type: domain.challenge_type,
          wildcard: domain.wildcard?,
          temporary: domain.temporary?
        }
      end
    end.sort_by { |certificate| [ certificate[:expires_at] || "9999", certificate[:hostname] ] }
  end

  def proxy_warnings
    ActivityEvent
      .where(project_id: server.project_ids, action: "warning")
      .where("message LIKE ?", "Proxy routing problem detected%")
      .limit(10)
      .map do |event|
        {
          id: event.id,
          project_name: event.project&.name,
          service_name: event.service_name,
          message: event.message,
          created_at: event.created_at&.iso8601
        }
      end
  end

  def managed_settings
    return {} if server.external_proxy?

    result = engine.run("traefik:report --global --format json")
    return {} unless result[:success]

    report = JSON.parse(result[:output].to_s)
    SAFE_REPORT_SETTINGS.each_with_object({}) do |(key, report_key), settings|
      settings[key] = report[report_key] if report.key?(report_key)
    end
  rescue JSON::ParserError
    {}
  end

  def normalize_container(row)
    {
      id: row["ID"].to_s[0, 12],
      name: container_name(row),
      image: row["Image"].to_s,
      status: row["Status"].to_s,
      state: row["State"].to_s,
      running: row["State"].to_s == "running",
      ports: row["Ports"].to_s,
      networks: row["Networks"].to_s
    }
  end

  def container_name(row)
    row["Names"].to_s.split(",").first.to_s.sub(%r{\A/}, "").presence
  end
end
