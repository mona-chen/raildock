# Manages a per-project Docker network for private service-to-service communication.
# Each project gets its own network (e.g. "raildock-42") so services can reach
# each other by internal hostname without exposing them to the public internet.
class ProjectNetworkManager
  NETWORK_PREFIX = "raildock"

  def initialize(project, engine)
    @project = project
    @engine = engine
  end

  def network_name
    @network_name ||= "#{NETWORK_PREFIX}-#{project.id}"
  end

  # Ensure the project's private network exists on the server.
  def ensure_network!
    result = engine.network_list
    return if result[:output]&.include?(network_name)
    engine.network_create(network_name)
  rescue => e
    Rails.logger.error "Failed to create network #{network_name}: #{e.message}"
  end

  # Connect a Dokku app to the project's private network.
  def connect_service(service)
    ensure_network!
    engine.network_connect(service.dokku_app_name, network_name)
    service.update!(internal_hostname: build_internal_hostname(service))
  rescue => e
    Rails.logger.error "Failed to connect #{service.dokku_app_name} to #{network_name}: #{e.message}"
  end

  # Disconnect a Dokku app from the project's private network.
  def disconnect_service(service)
    engine.network_disconnect(service.dokku_app_name, network_name)
  rescue => e
    Rails.logger.warn "Failed to disconnect #{service.dokku_app_name} from #{network_name}: #{e.message}"
  end

  # Build the internal hostname for a service within the project network.
  # Format: <service-name>.<project-network>.internal
  def build_internal_hostname(service)
    safe_name = service.name.to_s.downcase.gsub(/[^a-z0-9-]/, '-')
    "#{safe_name}.#{network_name}.internal"
  end

  # Inject internal hostnames as env vars for all linked services.
  # Apps can then use e.g. POSTGRES_HOST=postgres.raildock-42.internal
  def inject_internal_hostnames(service)
    return if service.linked_services.blank?

    service.linked_services.each do |linked|
      hostname = build_internal_hostname(linked)
      env_key = "#{linked.name.upcase.gsub(/[^A-Z0-9]/, '_')}_INTERNAL_HOST"
      engine.config_set(service.dokku_app_name, env_key, hostname)
    end
  end

  private

  attr_reader :project, :engine
end
