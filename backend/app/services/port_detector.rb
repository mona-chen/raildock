require "json"
require "shellwords"

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

    # Try 3: Inspect the running container's actual listening sockets. This is
    # more reliable than ports:report when RailDock previously fell back to 5000.
    port = detect_from_listening_ports(app_name)
    return port if port

    # Try 4: Docker EXPOSE metadata (unreliable — often wrong)
    port = detect_from_container(app_name)
    return port if port

    # Try 5: Dokku's ports:report (reflects configured mapping, which may be stale)
    port = detect_from_ports_report(app_name)
    return port if port

    # Try 6: Datastore plugin info (for postgres, redis, etc.)
    port = detect_from_datastore_info(service, app_name)
    return port if port

    # Try 7: Known default ports by service type
    port = default_port_for_subtype(service.subtype)
    return port if port

    # Try 8: Generic fallback based on deployment method
    service.docker_image.present? ? 80 : 5000
  rescue => e
    Rails.logger.error "Port detection failed for #{app_name}: #{e.message}"
    nil
  end

  private

  def detect_from_container(app_name)
    return unless @host_engine

    # Dokku tags the built image as dokku/<app>:latest. The running container
    # may still be named <app>.web.1.upcoming-<id> right after ps:rebuild, so
    # inspect the image to avoid the rename race.
    target = @host_engine.dokku_container_name(app_name) || "dokku/#{app_name}:latest"

    result = @host_engine.docker_inspect(target, format: "{{json .Config.ExposedPorts}}")
    return unless result[:success]

    ports = JSON.parse(result[:output]).to_h.keys.filter_map { |mapping| mapping.to_s.split("/").first.to_i.presence }
    ports.min
  rescue JSON::ParserError => e
    Rails.logger.warn "Docker exposed-port parse failed for #{app_name}: #{e.message}"
    nil
  end

  # Read /proc/net/tcp from the running container to find the port the process
  # is actually listening on. This avoids Dokku's 5000 fallback when the app
  # listens on a different port (e.g. Dockerfile EXPOSE 3000 + Puma on PORT).
  def detect_from_listening_ports(app_name)
    return unless @host_engine

    container = @host_engine.dokku_container_name(app_name)
    return unless container.present?

    result = @host_engine.run("docker exec #{Shellwords.escape(container)} sh -c 'cat /proc/net/tcp /proc/net/tcp6 2>/dev/null'")
    return unless result[:success]

    ports = parse_proc_net_tcp(result[:output])
    return nil if ports.empty?

    # Prefer non-system ports (>1024). If only system ports are listening,
    # fall back to the smallest one.
    non_system = ports.select { |p| p > 1024 }
    non_system.any? ? non_system.min : ports.min
  rescue => e
    Rails.logger.warn "Listening-port detection failed for #{app_name}: #{e.message}"
    nil
  end

  def parse_proc_net_tcp(output)
    ports = []
    output.each_line do |line|
      fields = line.split
      next if fields.size < 4
      next if fields[0] == "sl" # header

      local_address = fields[1]
      state = fields[3]
      next unless state == "0A" # TCP_LISTEN

      _ip_hex, port_hex = local_address.split(":", 2)
      next if port_hex.blank?

      port = port_hex.to_i(16)
      ports << port if port > 0
    end
    ports.uniq
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
