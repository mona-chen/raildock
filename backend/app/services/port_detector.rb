require "json"

class PortDetector
  def initialize(engine, host_engine: nil)
    @engine = engine
    @host_engine = host_engine
  end

  # Detect the port an app listens on using Dokku's built-in commands.
  # The Dokku SSH user intercepts raw Docker commands, so we use Dokku's
  # native reporting instead of `docker inspect`.
  #
  # Priority: manifest port > domain target_port > Docker EXPOSE > ports:report > defaults.
  # Docker's EXPOSE directive is unreliable — many Dockerfiles EXPOSE 80 while the
  # app actually listens on a different port (e.g. Rails on 3000).  The manifest's
  # `port` field and domain `target_port` are the authoritative sources.
  #
  # Returns the port number or nil if detection fails.
  def detect(service)
    app_name = service.dokku_app_name

    # Try 1: Manifest-declared port (authoritative — set by the user)
    port = service.port
    return port if port.present? && port > 0

    # Try 2: Domain target_port (set by reconciler from manifest port)
    port = service.domains.pick(:target_port)
    return port if port.present? && port > 0

    # Try 3: Dokku's ports:report (reflects actual runtime port mapping)
    port = detect_from_ports_report(app_name)
    return port if port

    # Try 4: Docker EXPOSE metadata (unreliable — often wrong)
    port = detect_from_container(app_name)
    return port if port

    # Try 5: Datastore plugin info (for postgres, redis, etc.)
    port = detect_from_datastore_info(service, app_name)
    return port if port

    # Try 6: Known default ports by service type
    port = default_port_for_subtype(service.subtype)
    return port if port

    # Try 7: Generic fallback based on deployment method
    service.docker_image.present? ? 80 : 5000
  rescue => e
    Rails.logger.error "Port detection failed for #{app_name}: #{e.message}"
    nil
  end

  private

  def detect_from_container(app_name)
    return unless @host_engine

    container = @host_engine.dokku_container_name(app_name)
    return unless container

    result = @host_engine.docker_inspect(container, format: "{{json .Config.ExposedPorts}}")
    return unless result[:success]

    ports = JSON.parse(result[:output]).to_h.keys.filter_map { |mapping| mapping.to_s.split("/").first.to_i.presence }
    ports.min
  rescue JSON::ParserError => e
    Rails.logger.warn "Docker exposed-port parse failed for #{app_name}: #{e.message}"
    nil
  end

  # Parse Dokku's `ports:report` output to extract the detected container port.
  # Format: "Ports map detected: http:80:3000" → returns 3000
  def detect_from_ports_report(app_name)
    result = @engine.run("ports:report #{app_name}")
    return nil unless result[:success]

    # Look for "Ports map detected:" line
    detected_line = result[:output].lines.find { |l| l.include?("Ports map detected") }
    return nil unless detected_line

    # Parse: "http:80:3000 https:443:3000" → extract the container port (last number)
    # Dokku reports as "scheme:host_port:container_port"
    match = detected_line.match(/:\s*(\S+)/)
    return nil unless match

    mappings = match[1].split
    return nil if mappings.empty?

    # Take the first mapping and extract container port
    first_mapping = mappings.first
    parts = first_mapping.split(":")
    return nil unless parts.length >= 3

    port = parts.last.to_i
    port > 0 ? port : nil
  rescue => e
    Rails.logger.warn "ports:report parse failed for #{app_name}: #{e.message}"
    nil
  end

  # For datastore plugins (postgres, redis, mysql, mongo), use the plugin's
  # info command to extract the port from the DSN.
  def detect_from_datastore_info(service, app_name)
    case service.subtype
    when "postgres"
      detect_from_dsn("postgres:info", app_name)
    when "redis"
      detect_from_dsn("redis:info", app_name)
    when "mysql", "mariadb"
      detect_from_dsn("mysql:info", app_name)
    when "mongo"
      detect_from_dsn("mongo:info", app_name)
    else
      nil
    end
  rescue => e
    Rails.logger.warn "Datastore info parse failed for #{app_name}: #{e.message}"
    nil
  end

  # Parse DSN line from plugin info output to extract port.
  # Format: "Dsn: postgres://...:5432/..." → returns 5432
  def detect_from_dsn(command, app_name)
    result = @engine.run("#{command} #{app_name}")
    return nil unless result[:success]

    dsn_line = result[:output].lines.find { |l| l.match?(/Dsn:\s+\S+:\/\//) }
    return nil unless dsn_line

    # DSN format: scheme://user:pass@host:port/db
    match = dsn_line.match(/@\S+:(\d+)\//)
    return nil unless match

    port = match[1].to_i
    port > 0 ? port : nil
  rescue => e
    Rails.logger.warn "DSN parse failed for #{app_name}: #{e.message}"
    nil
  end

  # Known default ports for common service types.
  def default_port_for_subtype(subtype)
    case subtype
    when "postgres" then 5432
    when "redis" then 6379
    when "mysql", "mariadb" then 3306
    when "mongo" then 27017
    when "elasticsearch" then 9200
    when "rabbitmq" then 5672
    when "memcached" then 11211
    else nil
    end
  end
end
