require "shellwords"

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

    # Stop Dokku's managed Traefik and disable the global proxy plugin.
    # These are idempotent — safe to call on every deploy.
    engine.traefik_stop
    engine.proxy_set_global("none")

    proxy_result = engine.proxy_disable(service.dokku_app_name)
    return proxy_result unless proxy_result[:success]

    ports_result = engine.ports_clear(service.dokku_app_name)
    return ports_result unless ports_result[:success]

    old_labels = service.config&.fetch(MANAGED_LABELS_KEY, {}) || {}
    new_labels = build_labels

    old_labels.each do |key, value|
      next if new_labels[key] == value

      return failure("remove label #{key}") unless remove_label(key, value)
    end
    new_labels.each do |key, value|
      next if old_labels[key] == value

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

  # Write labels directly to Dokku's docker-options config files.
  # This bypasses dokku docker-options:add whose Go shell parser cannot
  # handle parentheses and backticks in Traefik rule values like Host(\`domain\`).
  def add_label(key, value)
    %w[deploy run].all? do |phase|
      label_line = "--label=#{key}=#{value}"
      engine.run("echo #{Shellwords.escape(label_line)} >> #{options_file(phase)}")[:success]
    end
  end

  def remove_label(key, value)
    label_line = "--label=#{key}=#{value}"
    %w[deploy run].all? do |phase|
      # Use grep -v to remove matching lines; write back only if file exists
      engine.run("test -f #{options_file(phase)} && grep -vF #{Shellwords.escape(label_line)} #{options_file(phase)} > #{options_file(phase)}.tmp && mv #{options_file(phase)}.tmp #{options_file(phase)} || true")[:success]
    end
  end

  def options_file(phase)
    "/var/lib/dokku/config/docker-options/#{service.dokku_app_name}/_default_.#{phase}"
  end

  def failure(action)
    { success: false, output: "Failed to #{action} for #{service.dokku_app_name}" }
  end
end
