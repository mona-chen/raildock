class ExternalProxyConfigurator
  MANAGED_LABELS_KEY = "_externalProxyLabels"

  def initialize(service, engine, host_engine)
    @service = service
    @server = service.project.server
    @engine = engine
    @host_engine = host_engine
  end

  def apply!
    return { success: true } unless server&.external_proxy?

    network_result = host_engine.docker_network_inspect(server.external_proxy_network)
    return { success: false, output: "External proxy network '#{server.external_proxy_network}' was not found" } unless network_result[:success]

    # External mode owns routing labels directly. Disabling Dokku's proxy keeps
    # the traefik-vhosts hook from adding its own routers to the container.
    engine.traefik_stop
    proxy_result = engine.proxy_disable(service.dokku_app_name)
    return proxy_result unless proxy_result[:success]

    ports_result = engine.ports_clear(service.dokku_app_name)
    return ports_result unless ports_result[:success]

    new_labels = build_labels
    previous_labels = service.config&.fetch(MANAGED_LABELS_KEY, {}) || {}

    # Remove the legacy labels file so upgrading installations cannot receive
    # a second copy if the Dokku proxy is later re-enabled manually.
    host_engine.run("truncate -s 0 #{labels_file} || true")

    previous_labels.each do |key, value|
      remove_label(key, value)
    end

    new_labels.each do |key, value|
      return failure("add label #{key}") unless add_label(key, value)
    end

    service.config = (service.config || {}).merge(MANAGED_LABELS_KEY => new_labels)
    service.save!
    { success: true }
  end

  private

  attr_reader :service, :server, :engine, :host_engine

  def build_labels
    generated = {
      "traefik.enable" => "true",
      "traefik.docker.network" => server.external_proxy_network
    }
    service.domains.each do |domain|
      generated.merge!(TraefikLabelBuilder.new(service, domain, server: server).build_labels)
    end

    # The loadbalancer port is a service-level label, but TraefikLabelBuilder
    # generates it per-domain with the same key — the last domain processed
    # wins.  Temporary/sslip domains can have a stale target_port (e.g. 5000)
    # that overwrites the correct port from the primary domain.
    # Determine the port once, using the authoritative priority chain, then
    # drop every per-domain port label so only the resolved target survives.
    app_name = service.dokku_app_name
    target = effective_target_port
    generated.delete_if { |key, _| key.include?("loadbalancer.server.port") }

    # Pin the backend to the running container by NAME rather than letting
    # Traefik auto-detect a network IP.  When an app sits on several networks
    # (app network + external proxy network + docker0), Traefik can pick an IP
    # that is not routable from the proxy container and requests hang.
    # <app>.web.1 resolves via Docker's embedded DNS inside Traefik's namespace,
    # which is always routable.  Fall back to the plain port label when the
    # container is not running yet (e.g. first-time service creation).
    container = host_engine.dokku_container_name(app_name)
    if container.present?
      generated["traefik.http.services.#{app_name}-web.loadbalancer.server.url"] = "http://#{container}:#{target}"
    else
      generated["traefik.http.services.#{app_name}-web.loadbalancer.server.port"] = target.to_s
    end

    traefik_config = service.config&.dig("traefik") || {}
    configured = traefik_config["labels"].is_a?(Hash) ? traefik_config["labels"] : traefik_config
    configured = configured.select { |_key, value| value.is_a?(String) || value.is_a?(Numeric) || [ true, false ].include?(value) }
    server.external_proxy_default_labels.to_h.merge(generated).merge(configured).transform_values(&:to_s)
  end

  # Choose the port Traefik should forward to.
  #
  # Priority:
  #   1. An explicit domain target_port (user override per domain).
  #   2. The port the running container is actually listening on. This catches
  #      cases where the Dockerfile or startup command changed and the old
  #      manifest port is now stale.
  #   3. The manifest-declared service.port.
  #   4. Any previously auto-detected port.
  #   5. Dokku's generic fallback (5000).
  def effective_target_port
    domain_target = service.domains.where(temporary: false).where.not(target_port: nil).pick(:target_port)
    return domain_target if domain_target.present? && domain_target > 0

    actual = PortDetector.new(engine, host_engine: host_engine).detect_actual(service)
    if actual.present? && actual > 0
      if service.port.present? && service.port > 0 && service.port != actual
        Rails.logger.warn "Service #{service.dokku_app_name} manifest port #{service.port} does not match actual listening port #{actual}; using actual port"
      end
      return actual
    end

    return service.port if service.port.present? && service.port > 0
    return service.detected_port if service.detected_port.present? && service.detected_port > 0

    5000
  end

  def add_label(key, value)
    engine.docker_option_add(
      service.dokku_app_name,
      "deploy",
      docker_label_option(key, value),
      process: "web"
    )[:success]
  end

  def remove_label(key, value)
    engine.docker_option_remove(
      service.dokku_app_name,
      "deploy",
      docker_label_option(key, value),
      process: "web"
    )
  end

  def docker_label_option(key, value)
    escaped_value = value.to_s.gsub("`", '\\\`')
    %(--label "#{key}=#{escaped_value}")
  end

  def labels_file
    "/var/lib/dokku/config/traefik/#{service.dokku_app_name}/labels"
  end

  def failure(action)
    { success: false, output: "Failed to #{action} for #{service.dokku_app_name}" }
  end
end
