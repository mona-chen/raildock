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

  # Ensure the project's private network exists on the server.
  def ensure_network!
    result = engine.network_list
    return if result[:output]&.include?(network_name)

    # Create via Dokku first (for metadata tracking)
    engine.network_create(network_name)
    # Also create via Docker directly in case Dokku's command is delayed
    host_engine.docker_network_create(network_name)
  rescue => e
    Rails.logger.error "Failed to create network #{network_name}: #{e.message}"
  end

  # Connect a Dokku app to the project's private network.
  # Uses attach-post-create so the network is attached BEFORE the container
  # starts, avoiding DNS race conditions on app boot.
  def connect_service(service)
    ensure_network!

    # Tell Dokku to attach the network on container creation (persistent)
    engine.run("network:set #{service.dokku_app_name} attach-post-create #{network_name}")

    # If the container is already running, connect it directly with aliases
    container = host_engine.dokku_container_name(service.dokku_app_name)
    connect_container_with_aliases(container, [service.name.to_s.downcase.gsub(/[^a-z0-9-]/, '-')])

    service.update!(internal_hostname: build_internal_hostname(service))
  rescue => e
    Rails.logger.error "Failed to connect #{service.dokku_app_name} to #{network_name}: #{e.message}"
  end

  # Disconnect a Dokku app from the project's private network.
  def disconnect_service(service)
    engine.network_disconnect(service.dokku_app_name, network_name)
    engine.run("network:set #{service.dokku_app_name} attach-post-create")
  rescue => e
    Rails.logger.warn "Failed to disconnect #{service.dokku_app_name} from #{network_name}: #{e.message}"
  end

  # Build the internal hostname for a service within the project network.
  # On Docker custom bridge networks, containers resolve each other by their
  # network alias (the short service name). No `.internal` TLD needed — that
  # only works with custom DNS resolvers (Railway, Kubernetes, etc.).
  #
  # What actually works: redis, postgres, activepieces
  # What doesn't work: redis.raildock-1.internal
  def build_internal_hostname(service)
    service.name.to_s.downcase.gsub(/[^a-z0-9-]/, '-')
  end

  # Inject alias hostnames as env vars for all linked services.
  # Apps can then use e.g. POSTGRES_HOST=postgres (the Docker alias).
  def inject_internal_hostnames(service)
    return if service.linked_services.blank?

    service.linked_services.each do |linked|
      alias_name = build_internal_hostname(linked)
      env_key = "#{linked.name.upcase.gsub(/[^A-Z0-9]/, '_')}_HOST"
      engine.config_set(service.dokku_app_name, env_key, alias_name)
    end
  end

  # Ensure all linked services have network aliases on the project network.
  # Call this after linking to make sure the target container is discoverable
  # by its short name (e.g. "redis", "postgres").
  def ensure_linked_aliases(service)
    return if service.linked_services.blank?

    service.linked_services.each do |linked|
      container = host_engine.dokku_container_name(linked.dokku_app_name)
      alias_name = linked.name.to_s.downcase.gsub(/[^a-z0-9-]/, '-')
      connect_container_with_aliases(container, [alias_name])
    end
  end

  private

  attr_reader :project, :engine, :host_engine

  # Connect a running container to the project network with aliases.
  # If already connected, disconnect first to update aliases.
  def connect_container_with_aliases(container, aliases)
    return if container.blank?
    return if aliases.empty?

    # Disconnect first to ensure aliases are updated
    host_engine.docker_network_disconnect(container, network_name)
    # Reconnect with aliases
    result = host_engine.docker_network_connect(container, network_name, aliases: aliases)
    unless result[:success]
      Rails.logger.warn "Failed to add aliases #{aliases} to #{container}: #{result[:output]}"
    end
  rescue => e
    Rails.logger.warn "Alias connect failed for #{container}: #{e.message}"
  end
end
