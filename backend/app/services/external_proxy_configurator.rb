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

    traefik_config = service.config&.dig("traefik") || {}
    configured = traefik_config["labels"].is_a?(Hash) ? traefik_config["labels"] : traefik_config
    configured = configured.select { |_key, value| value.is_a?(String) || value.is_a?(Numeric) || [ true, false ].include?(value) }
    server.external_proxy_default_labels.to_h.merge(generated).merge(configured).transform_values(&:to_s)
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
