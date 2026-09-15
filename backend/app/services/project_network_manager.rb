# frozen_string_literal: true

# Manages a per-project Docker network for private service-to-service communication.
# Each project gets its own network (e.g. "raildock-42") so services can reach
# each other by internal hostname without exposing them to the public internet.
class ProjectNetworkManager
  NETWORK_PREFIX = "raildock"

  def initialize(project, engine)
    @project = project
    @engine = engine
    @host_engine = HostEngine.new(project.server)
  end

  def network_name
    @network_name ||= project.network_name.presence || "#{NETWORK_PREFIX}-#{project.id}"
  end

  def ensure_network!
    result = engine.network_list
    return if result[:output]&.include?(network_name)

    engine.network_create(network_name)
    host_engine.docker_network_create(network_name)
  rescue => e
    Rails.logger.error "Failed to create network #{network_name}: #{e.message}"
  end

  # Connect a service to the project network AND add network aliases for
  # ALL of its linked targets. This ensures that when a container A declares
  # a dependency on container B by name (e.g. PG_CONSOLE_DB_HOST=autobase-db),
  # container B is reachable by that name via the shared Docker network DNS.
  #
  # Also sets Dokku's attach-post-create so the network is attached BEFORE the
  # container starts, avoiding DNS race conditions on app boot.
  def connect_service(service)
    attach_result = configure_attach_networks(service)
    return attach_result unless attach_result[:success]

    # Wait for the app container to exist before trying to connect it. After a
    # fresh deploy the container can take a few seconds to appear in docker ps.
    container = wait_for_linked_container(service.dokku_app_name)
    if container.present?
      result = connect_container_with_aliases(container, [ build_internal_hostname(service) ])
      return result unless result[:success]
    else
      return { success: false, output: "App container #{service.dokku_app_name} was not found" }
    end

    if service.linked_services.any?
      service.linked_services.each do |linked|
        # Skip linked services that aren't deployed yet — they'll be connected
        # when they deploy. Don't block the current service's deploy.
        unless linked.status == "running"
          Rails.logger.info "Skipping network alias for #{linked.dokku_app_name}: not deployed (status=#{linked.status})"
          next
        end

        linked_container = wait_for_linked_container(linked.dokku_app_name)
        linked_alias = linked.name.to_s.downcase.gsub(/[^a-z0-9-]/, "-")
        if linked_container.present?
          result = connect_container_with_aliases(linked_container, [ linked_alias ])
          return result unless result[:success]
          unless wait_for_network_alias(linked_container, linked_alias)
            return { success: false, output: "Network alias #{linked_alias} did not propagate for #{linked_container}" }
          end
        else
          Rails.logger.warn "Linked container #{linked.dokku_app_name} not found in Docker, skipping"
          next
        end
      end
    end

    service.update!(internal_hostname: build_internal_hostname(service))
    { success: true }
  rescue => e
    Rails.logger.error "Failed to connect #{service.dokku_app_name} to #{network_name}: #{e.message}"
    { success: false, output: e.message }
  end

  def configure_attach_networks(service)
    ensure_network!

    # Private project network — attach-post-create so containers can resolve
    # linked services (e.g. rustfs, mysql) at boot time. Only one network here
    # to avoid the Dokku bug where attach-post-create only attaches the first.
    result = engine.run("network:set #{service.dokku_app_name} attach-post-create #{network_name}")
    return result unless result[:success]

    # Every post-deploy network has to be written in ONE call. Dokku replaces
    # the whole attach-post-deploy list on each `network:set`, so setting the
    # proxy network and then an external network (e.g. matrix-postgres) drops
    # whichever was set first. The container then deploys off the proxy
    # network and every domain for the service answers 502.
    networks = attach_post_deploy_networks(service)
    return { success: true } if networks.empty?

    engine.run("network:set #{service.dokku_app_name} attach-post-deploy #{networks.join(',')}")
  end

  # Every network a container must join after (and at) deploy: the external
  # proxy network that fronts the service's domains, plus any user-selected
  # external networks (e.g. matrix-postgres, synapse-network). Order is stable
  # and duplicates are dropped so repeated deploys stay idempotent.
  def attach_post_deploy_networks(service)
    networks = []
    if service.service_type_app? && project.server&.external_proxy?
      networks << project.server.external_proxy_network.to_s.strip
    end

    Array(service.external_networks).each do |net_name|
      name = net_name.to_s.strip
      next if name.blank?

      # Verify the network exists on the host
      unless host_engine.docker_network_inspect(name)[:success]
        Rails.logger.warn "External network '#{name}' not found on server, skipping for #{service.dokku_app_name}"
        next
      end

      networks << name
    end

    networks.reject(&:blank?).uniq
  end

  # Connect a service's running container to every network it must be on.
  # Dokku's attach-post-deploy hook normally does this, but a container that
  # was created before the networks were configured — or a hook that failed —
  # stays reachable only from the private network, and Traefik answers 502 for
  # every domain until the next deploy. Verify instead of assuming.
  def connect_to_post_deploy_networks(service)
    connect_to_networks(service, attach_post_deploy_networks(service))
  end

  # Connect a service's running container to its configured external networks.
  # Called after deploy completes so the container is immediately reachable on
  # those networks (not waiting for the next deploy's attach-post-deploy).
  def connect_to_external_networks(service)
    connect_to_networks(service, Array(service.external_networks).reject(&:blank?))
  end

  def disconnect_service(service)
    engine.network_disconnect(service.dokku_app_name, network_name)
    engine.run("network:set #{service.dokku_app_name} attach-post-create")
  rescue => e
    Rails.logger.warn "Failed to disconnect #{service.dokku_app_name}: #{e.message}"
  end

  def build_internal_hostname(service)
    service.name.to_s.downcase.gsub(/[^a-z0-9-]/, "-")
  end

  def inject_internal_hostnames(service)
    return { success: true } if service.linked_services.blank?

    service.linked_services.each do |linked|
      alias_name = build_internal_hostname(linked)
      env_key = "#{linked.name.upcase.gsub(/[^A-Z0-9]/, '_')}_HOST"
      result = engine.config_set(service.dokku_app_name, env_key, alias_name)
      return result unless result[:success]
    end

    { success: true }
  end

  # Ensure all linked services have network aliases on the project network.
  # Waits for linked service containers to be running before attempting to connect.
  def ensure_linked_aliases(service)
    return { success: true } if service.linked_services.blank?

    service.linked_services.each do |linked|
      # Skip linked services that aren't deployed yet
      unless linked.status == "running"
        Rails.logger.info "Skipping alias for #{linked.dokku_app_name}: not deployed (status=#{linked.status})"
        next
      end

      container = wait_for_linked_container(linked.dokku_app_name)
      unless container
        Rails.logger.warn "Linked container #{linked.dokku_app_name} not found in Docker, skipping"
        next
      end

      alias_name = linked.name.to_s.downcase.gsub(/[^a-z0-9-]/, "-")
      result = connect_container_with_aliases(container, [ alias_name ])
      return result unless result[:success]
      unless wait_for_network_alias(container, alias_name)
        return { success: false, output: "Network alias #{alias_name} did not propagate for #{container}" }
      end
    end

    { success: true }
  end

  def wait_for_linked_container(app_name, timeout: 60)
    start_time = Time.now
    while Time.now - start_time < timeout
      container = host_engine.dokku_container_name(app_name)
      return container if container.present? && host_engine.container_running?(container)
      sleep 1
    end
    # Try one more time without the running check
    container = host_engine.dokku_container_name(app_name)
    container if container.present?
  end

  private

  attr_reader :project, :engine, :host_engine

  # Attach a running container to each network and report the ones that did
  # not make it, so a caller can surface a service that would otherwise only
  # be reachable from the private network.
  def connect_to_networks(service, networks)
    networks = Array(networks).reject(&:blank?).uniq
    return { success: true, connected: [] } if networks.empty?

    container = wait_for_linked_container(service.dokku_app_name)
    return { success: false, output: "Container #{service.dokku_app_name} not found" } if container.blank?

    connected = []
    missing = []

    networks.each do |net_name|
      unless host_engine.docker_network_inspect(net_name)[:success]
        Rails.logger.warn "Network '#{net_name}' not found on server, skipping connect for #{service.dokku_app_name}"
        missing << net_name
        next
      end

      # Disconnect first to avoid duplicate connections and stale endpoints.
      host_engine.docker_network_disconnect(container, net_name)
      result = host_engine.docker_network_connect(container, net_name)
      if result[:success]
        connected << net_name
      else
        Rails.logger.warn "Failed to connect #{service.dokku_app_name} to network '#{net_name}': #{result[:output]}"
        missing << net_name
      end
    end

    return { success: true, connected: connected } if missing.empty?

    { success: false, output: "Container #{container} is not attached to: #{missing.join(', ')}", connected: connected }
  end

  def connect_container_with_aliases(container, aliases, wait: true)
    return { success: true } if aliases.empty?

    # If container is not provided, try to find it or wait for it
    if container.blank?
      return { success: false, output: "Container name is blank" }
    end

    # Wait for container to be running if requested
    if wait
      wait_start = Time.now
      while Time.now - wait_start < 30
        break if host_engine.container_running?(container)
        sleep 1
      end
      unless host_engine.container_running?(container)
        return { success: false, output: "Container #{container} is not running" }
      end
    end

    host_engine.docker_network_disconnect(container, network_name)
    result = host_engine.docker_network_connect(container, network_name, aliases: aliases)
    return result unless result[:success]

    { success: true }
  rescue => e
    Rails.logger.warn "Alias connect failed for #{container}: #{e.message}"
    { success: false, output: e.message }
  end
  public :connect_container_with_aliases

  # Wait for a container to be registered in the network with its alias.
  # Polls slowly to avoid hammering the host with SSH commands during deploys.
  def wait_for_network_alias(container, alias_name, timeout: 30)
    start_time = Time.now
    while Time.now - start_time < timeout
      result = host_engine.docker_network_inspect(network_name)
      if result[:success] && result[:output].include?(alias_name)
        return true
      end
      sleep 2
    end
    false
  end
end
