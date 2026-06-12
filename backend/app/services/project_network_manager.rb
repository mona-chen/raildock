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
    ensure_network!

    engine.run("network:set #{service.dokku_app_name} attach-post-create #{network_name}")

    container = host_engine.dokku_container_name(service.dokku_app_name)
    connect_container_with_aliases(container, [ service.name.to_s.downcase.gsub(/[^a-z0-9-]/, "-") ])

    if service.linked_services.any?
      service.linked_services.each do |linked|
        linked_container = host_engine.dokku_container_name(linked.dokku_app_name)
        linked_alias = linked.name.to_s.downcase.gsub(/[^a-z0-9-]/, "-")
        connect_container_with_aliases(linked_container, [ linked_alias ])
        unless wait_for_network_alias(linked_container, linked_alias)
          Rails.logger.warn "Network alias #{linked_alias} did not propagate for #{linked_container}"
        end
      end
    end

    service.update!(internal_hostname: build_internal_hostname(service))
  rescue => e
    Rails.logger.error "Failed to connect #{service.dokku_app_name} to #{network_name}: #{e.message}"
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
    return if service.linked_services.blank?

    service.linked_services.each do |linked|
      alias_name = build_internal_hostname(linked)
      env_key = "#{linked.name.upcase.gsub(/[^A-Z0-9]/, '_')}_HOST"
      engine.config_set(service.dokku_app_name, env_key, alias_name)
    end
  end

  # Ensure all linked services have network aliases on the project network.
  # Waits for linked service containers to be running before attempting to connect.
  def ensure_linked_aliases(service)
    return if service.linked_services.blank?

    service.linked_services.each do |linked|
      # Wait for linked container to be running
      container = wait_for_linked_container(linked.dokku_app_name)
      unless container
        Rails.logger.warn "Linked container for #{linked.dokku_app_name} not found after waiting"
        next
      end

      alias_name = linked.name.to_s.downcase.gsub(/[^a-z0-9-]/, "-")
      connect_container_with_aliases(container, [ alias_name ])
      unless wait_for_network_alias(container, alias_name)
        Rails.logger.warn "Network alias #{alias_name} did not propagate for #{container}"
      end
    end
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
    return if aliases.empty?

    # If container is not provided, try to find it or wait for it
    if container.blank?
      Rails.logger.warn "connect_container_with_aliases called with blank container"
      return
    end

    # Wait for container to be running if requested
    if wait
      wait_start = Time.now
      while Time.now - wait_start < 30
        break if host_engine.container_running?(container)
        sleep 1
      end
      unless host_engine.container_running?(container)
        Rails.logger.warn "Container #{container} not running after 30s wait, skipping alias connect"
        return
      end
    end

    host_engine.docker_network_disconnect(container, network_name)
    result = host_engine.docker_network_connect(container, network_name, aliases: aliases)
    unless result[:success]
      Rails.logger.warn "Failed to add aliases #{aliases} to #{container}: #{result[:output]}"
    end
  rescue => e
    Rails.logger.warn "Alias connect failed for #{container}: #{e.message}"
  end

  # Wait for a container to be registered in the network with its alias
  def wait_for_network_alias(container, alias_name, timeout: 30)
    start_time = Time.now
    while Time.now - start_time < timeout
      result = host_engine.docker_network_inspect(network_name)
      if result[:success] && result[:output].include?(alias_name)
        return true
      end
      sleep 1
    end
    false
  end
end
