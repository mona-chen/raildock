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

    # External Traefik network — attach-post-deploy (after health checks).
    # Not needed at boot, only for Traefik to discover the container.
    if service.service_type_app? && project.server&.external_proxy?
      engine.run("network:set #{service.dokku_app_name} attach-post-deploy #{project.server.external_proxy_network}")
    end

    { success: true }
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
