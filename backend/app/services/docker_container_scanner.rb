require "json"

# Scans a remote Docker host for running/existing containers that could be
# imported into RailDock as Dokku apps/services.
class DockerContainerScanner
  DB_IMAGE_SUBTYPES = {
    /postgres/ => "postgres",
    /redis/ => "redis",
    /mariadb/ => "mariadb",
    /mysql/ => "mysql",
    /mongo/ => "mongo"
  }.freeze

  attr_reader :server

  def initialize(server)
    @server = server
  end

  # Returns an array of container hashes ready for the import UI.
  def scan
    result = host_engine.run(scan_command)
    return { success: false, error: result[:output] } unless result[:success]

    output = result[:output].to_s.strip
    return { success: true, containers: [] } if output.blank?

    containers = output.each_line.filter_map do |line|
      parse_container(JSON.parse(line))
    rescue JSON::ParserError
      nil
    end

    { success: true, containers: containers }
  rescue => e
    Rails.logger.error "DockerContainerScanner failed for server #{server.id}: #{e.message}"
    { success: false, error: e.message }
  end

  private

  def host_engine
    @host_engine ||= HostEngine.new(server)
  end

  def scan_command
    # xargs -r avoids running docker inspect when no containers exist.
    "docker ps -q | xargs -r -I {} docker inspect --format '{{json .}}' {}"
  end

  def parse_container(raw)
    name = container_name(raw)
    image = raw.dig("Config", "Image").to_s

    return nil if name.blank? || image.blank?

    service_type, subtype = classify_image(image)

    {
      id: raw["Id"].to_s[0, 12],
      name: name,
      image: image,
      status: raw.dig("State", "Status"),
      running: raw.dig("State", "Running") == true,
      created: raw["Created"],
      command: raw.dig("Config", "Cmd")&.join(" "),
      ports: parse_ports(raw),
      env: parse_env(raw),
      mounts: parse_mounts(raw),
      labels: raw.dig("Config", "Labels") || {},
      service_type: service_type,
      subtype: subtype
    }
  end

  def container_name(raw)
    # Names look like ["/container_name"]; Config.Hostname is also available.
    name = Array(raw["Names"]).first.to_s.sub(%r{^/}, "")
    name.presence || raw.dig("Config", "Hostname").to_s
  end

  def parse_env(raw)
    env = {}
    Array(raw.dig("Config", "Env")).each do |line|
      key, value = line.to_s.split("=", 2)
      env[key] = value if key.present?
    end
    env
  end

  def parse_ports(raw)
    bindings = raw.dig("HostConfig", "PortBindings") || {}
    exposed = raw.dig("Config", "ExposedPorts") || {}

    ports = []
    bindings.each do |container_port, host_bindings|
      Array(host_bindings).each do |binding|
        ports << {
          container_port: container_port.to_s.sub(%r{/\w+\z}, ""),
          host_port: binding["HostPort"],
          host_ip: binding["HostIp"]
        }
      end
    end

    # If nothing is published, still surface exposed ports so the UI can suggest them.
    if ports.empty?
      exposed.keys.each do |port|
        ports << { container_port: port.to_s.sub(%r{/\w+\z}, ""), host_port: nil, host_ip: nil }
      end
    end

    ports
  end

  def parse_mounts(raw)
    binds = Array(raw.dig("HostConfig", "Binds"))
    mounts = raw["Mounts"] || []

    # Prefer Mounts (rich metadata) over HostConfig.Binds.
    if mounts.any?
      mounts.map do |m|
        {
          source: m["Source"],
          destination: m["Destination"],
          type: m["Type"], # bind, volume, tmpfs
          mode: m["Mode"]
        }
      end
    else
      binds.map do |bind|
        parts = bind.split(":", 3)
        {
          source: parts[0],
          destination: parts[1],
          type: parts[0].start_with?("/") ? "bind" : "volume",
          mode: parts[2]
        }
      end
    end
  end

  def classify_image(image)
    lower = image.downcase
    DB_IMAGE_SUBTYPES.each do |pattern, subtype|
      return ["database", subtype] if lower.match?(pattern)
    end
    ["app", nil]
  end
end
