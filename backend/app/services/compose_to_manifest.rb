# frozen_string_literal: true

require "yaml"

# Converts Docker Compose YAML into RailDock manifest TOML.
#
# This is a best-effort converter — Docker Compose is far more expressive than
# RailDock's Dokku-native abstraction, so some features are dropped with warnings.
#
# Supported mappings:
#   services:         → [[services]]
#   image:            → docker_image + subtype detection
#   build:            → builder = "nixpacks" | "dockerfile", source = { type: "git" }
#   environment:      → [services.env]
#   ports:            → [[services.proxy.ports]]
#   volumes:          → [[services.storage]] (named volumes only; bind mounts flagged)
#   depends_on:       → [[links]]
#   healthcheck:      → [services.checks]
#   restart:          → ignored (Dokku handles this)
#   networks:         → ignored (Dokku uses its own networking)
#   entrypoint:       → WARNING (not supported)
#   command:          → start_command
#
# Usage:
#   converter = ComposeToManifest.new(coolify_yaml_content)
#   result = converter.convert
#   result.toml     # => "name = ..."
#   result.warnings # => ["Dropped unsupported feature: networks", ...]
class ComposeToManifest
  ConversionResult = Struct.new(:toml, :hash, :warnings, :metadata, keyword_init: true)

  # image pattern → { category:, subtype: }
  IMAGE_MAP = {
    /postgres/      => { category: "database", subtype: "postgres" },
    /mysql/         => { category: "database", subtype: "mysql" },
    /mariadb/       => { category: "database", subtype: "mariadb" },
    /mongo/         => { category: "database", subtype: "mongo" },
    /redis/         => { category: "cache",    subtype: "redis" },
    /memcached/     => { category: "cache",    subtype: "memcached" },
    /elasticsearch/ => { category: "search",   subtype: "elasticsearch" },
    /meilisearch/   => { category: "search",   subtype: "meilisearch" },
    /typesense/     => { category: "search",   subtype: "typesense" },
    /rabbitmq/      => { category: "queue",    subtype: "rabbitmq" },
    /kafka/         => { category: "queue",    subtype: "kafka" },
    /minio/         => { category: "service",  subtype: "s3" },
  }.freeze

  # Coolify metadata comment keys we care about
  METADATA_KEYS = %w[documentation slogan description category tags logo port icon].freeze

  def initialize(compose_yaml, metadata = {})
    @raw_yaml = compose_yaml
    @metadata = metadata
    @warnings = []
  end

  # ── Public API ──────────────────────────────────────────────

  def self.extract_coolify_metadata(yaml_content)
    metadata = {}
    yaml_content.each_line do |line|
      stripped = line.strip
      break if !stripped.empty? && !stripped.start_with?("#")
      next if stripped.empty?

      # Match "# key: value" or "#key: value"
      if stripped =~ /^#\s*(\w+):\s*(.*)$/
        key = $1.downcase
        val = $2.strip
        metadata[key] = val if METADATA_KEYS.include?(key)
      end
    end
    metadata
  end

  def convert
    compose = parse_compose
    return nil unless compose

    services_hash = compose["services"] || {}
    return nil if services_hash.empty?

    manifest = build_manifest(services_hash, compose)

    ConversionResult.new(
      toml: toml_string(manifest),
      hash: manifest,
      warnings: @warnings.uniq,
      metadata: @metadata
    )
  end

  # ── Parsing ─────────────────────────────────────────────────

  private

  def parse_compose
    # Strip metadata comments before YAML parsing
    clean_yaml = @raw_yaml.gsub(/^(#.*\n)+/, "")
    YAML.safe_load(clean_yaml, aliases: true)
  rescue Psych::SyntaxError => e
    @warnings << "YAML parse error: #{e.message}"
    nil
  end

  # ── Manifest Building ───────────────────────────────────────

  def build_manifest(services_hash, compose)
    services = []
    links = []

    services_hash.each do |name, config|
      svc = convert_service(name, config)
      services << svc if svc
    end

    # Build links from depends_on
    services_hash.each do |name, config|
      deps = config["depends_on"]
      next unless deps

      dep_names = deps.is_a?(Hash) ? deps.keys : Array(deps)
      dep_names.each do |dep|
        links << { "from" => name, "to" => dep }
      end
    end

    {
      "name" => @metadata["slogan"] || @metadata["description"] || "Imported Stack",
      "description" => @metadata["description"] || @metadata["slogan"] || "",
      "category" => coolify_category_to_raildock(@metadata["category"]),
      "services" => services,
      "links" => links
    }
  end

  def convert_service(name, config)
    image = config["image"]
    build = config["build"]

    if image
      info = detect_from_image(image)
    elsif build
      info = { category: "app", subtype: "docker", builder: "nixpacks" }
    else
      @warnings << "Service '#{name}' has no image or build context — skipped"
      return nil
    end

    # Skip one-off init / migration containers
    if config["restart"] == "no" || config["restart"] == "\"no\""
      @warnings << "Service '#{name}' is a one-off container (restart: no) — skipped"
      return nil
    end

    svc = {
      "name" => name,
      "category" => info[:category],
      "subtype" => info[:subtype]
    }

    # Builder / source
    if build
      svc["builder"] = info[:builder]
      svc["source"] = infer_source(build)
    elsif image
      svc["docker_image"] = normalize_image(image)
      svc["source"] = { "type" => "docker" }
    end

    # Environment variables
    env = convert_env(config["environment"])
    svc["env"] = env unless env.empty?

    # Ports → proxy
    ports = convert_ports(config["ports"])
    if ports.any?
      svc["proxy"] = {
        "enabled" => true,
        "type" => "traefik",
        "ports" => ports
      }
    end

    # Volumes → storage
    storage = convert_volumes(config["volumes"], name)
    svc["storage"] = storage if storage.any?

    # Healthcheck → checks
    checks = convert_healthcheck(config["healthcheck"])
    svc["checks"] = checks if checks

    # Command
    if config["command"] && !config["command"].to_s.empty?
      svc["start_command"] = Array(config["command"]).join(" ")
    end

    # Scaling defaults
    if info[:category] == "app"
      svc["scaling"] = { "web" => 1 }
    end

    # Flag unsupported features
    flag_unsupported(config, name)

    svc
  end

  # ── Detection Helpers ───────────────────────────────────────

  def detect_from_image(image)
    image_str = image.to_s.downcase
    IMAGE_MAP.each do |pattern, info|
      return info if image_str.match?(pattern)
    end
    { category: "app", subtype: "docker" }
  end

  def normalize_image(image)
    # Docker Compose images may include registry, namespace, tag
    # Keep as-is — Dokku handles dockerImage deployment
    image.to_s.strip
  end

  def infer_source(build)
    if build.is_a?(Hash)
      dockerfile = build["dockerfile"]
      if dockerfile && dockerfile.include?("nixpacks")
        return { "type" => "git" }
      end
    end
    { "type" => "git" }
  end

  # ── Field Converters ────────────────────────────────────────

  def convert_env(env)
    return {} unless env

    case env
    when Hash
      env.each_with_object({}) do |(k, v), h|
        h[k.to_s] = v.to_s
      end
    when Array
      result = {}
      env.each do |item|
        if item.to_s.include?("=")
          key, value = item.to_s.split("=", 2)
          result[key] = value || ""
        else
          # Variable reference like "FOO" — set empty placeholder
          result[item.to_s] = ""
        end
      end
      result
    else
      {}
    end
  end

  def convert_ports(ports)
    return [] unless ports.is_a?(Array)

    ports.filter_map do |p|
      case p
      when String
        if p.include?(":")
          parts = p.split(":")
          { "host" => parts[0].to_i, "container" => parts[1].to_i }
        else
          { "host" => 80, "container" => p.to_i }
        end
      when Hash
        published = p["published"] || p["target"]
        target = p["target"] || p["published"]
        if published && target
          { "host" => published.to_i, "container" => target.to_i }
        elsif target
          { "host" => 80, "container" => target.to_i }
        end
      when Integer
        { "host" => 80, "container" => p }
      end
    end
  end

  def convert_volumes(volumes, service_name)
    return [] unless volumes.is_a?(Array)

    volumes.filter_map do |vol|
      case vol
      when String
        if vol.include?(":")
          parts = vol.split(":")
          host = parts[0]
          container = parts[1]

          # Skip relative bind mounts (Coolify uses ./volumes/...)
          if host.start_with?("./") || host.start_with?("/")
            @warnings << "Bind mount '#{vol}' in '#{service_name}' dropped — use Dokku storage:mount manually"
            next
          end

          # Named volume
          { "host" => host, "container" => container }
        else
          # Anonymous volume — name it after the service
          { "host" => "#{service_name}-data", "container" => "/data" }
        end
      when Hash
        source = vol["source"] || ""
        target = vol["target"] || ""

        if source.start_with?("./") || source.start_with?("/")
          @warnings << "Bind mount '#{source}:#{target}' in '#{service_name}' dropped — use Dokku storage:mount manually"
          next
        end

        { "host" => source, "container" => target }
      end
    end
  end

  def convert_healthcheck(hc)
    return nil unless hc.is_a?(Hash)

    test = hc["test"]
    return nil unless test

    # Convert test array to a simple command string
    cmd = Array(test).join(" ")

    {
      "enabled" => true,
      "wait" => (hc["interval"] || "5s").to_s.scan(/\d+/).first.to_i,
      "timeout" => (hc["timeout"] || "30s").to_s.scan(/\d+/).first.to_i,
      "skip" => []
    }
  end

  # ── Unsupported Feature Flags ───────────────────────────────

  def flag_unsupported(config, name)
    unsupported = {
      "networks" => "custom Docker networks",
      "entrypoint" => "custom entrypoints",
      "labels" => "Traefik labels (RailDock manages proxy)",
      "profiles" => "Docker Compose profiles",
      "extra_hosts" => "extra_hosts",
      "cap_add" => "cap_add",
      "cap_drop" => "cap_drop",
      "sysctls" => "sysctls",
      "devices" => "devices",
      "secrets" => "Docker secrets",
      "configs" => "Docker configs",
      "deploy" => "Docker Swarm deploy options",
      "logging" => "custom logging drivers"
    }

    unsupported.each do |key, desc|
      if config.key?(key)
        @warnings << "Service '#{name}': #{desc} not supported — dropped"
      end
    end

    # Special check for bind mounts with inline content (Coolify feature)
    if config["volumes"].is_a?(Array)
      config["volumes"].each do |vol|
        if vol.is_a?(Hash) && vol["content"]
          @warnings << "Service '#{name}': inline file content volumes not supported — dropped"
        end
      end
    end
  end

  # ── Category Mapping ────────────────────────────────────────

  def coolify_category_to_raildock(cat)
    return "stack" unless cat

    cat = cat.to_s.downcase.strip
    case cat
    when "backend", "frontend", "web", "cms", "analytics", "monitoring",
         " productivity", "communication", "development", "security",
         "media", "ai", "automation", "tools"
      "stack"
    when "database"
      "stack"
    else
      "stack"
    end
  end

  # ── TOML Serialization ──────────────────────────────────────

  def toml_string(manifest)
    lines = []
    lines << %(name = "#{escape_toml_string(manifest["name"])}")
    lines << %(description = "#{escape_toml_string(manifest["description"])}")
    lines << %(category = "#{manifest["category"]}")
    lines << ""

    manifest["services"].each do |svc|
      lines << "[[services]]"
      lines << %(name = "#{svc["name"]}")
      lines << %(category = "#{svc["category"]}")
      lines << %(subtype = "#{svc["subtype"]}")

      lines << %(builder = "#{svc["builder"]}") if svc["builder"]
      lines << %(docker_image = "#{escape_toml_string(svc["docker_image"])}") if svc["docker_image"]
      lines << %(start_command = "#{escape_toml_string(svc["start_command"])}") if svc["start_command"]

      if svc["source"]
        lines << %(source = { type = "#{svc["source"]["type"]}" )
        lines[-1] += %(, repo = "#{svc["source"]["repo"]}") if svc["source"]["repo"]
        lines[-1] += %(, branch = "#{svc["source"]["branch"]}") if svc["source"]["branch"]
        lines[-1] += " }"
      end

      if svc["scaling"]
        lines << "  [services.scaling]"
        svc["scaling"].each do |k, v|
          lines << "    #{k} = #{v}"
        end
      end

      if svc["env"]
        lines << "  [services.env]"
        svc["env"].each do |k, v|
          lines << %(    #{k} = "#{escape_toml_string(v)}")
        end
      end

      if svc["proxy"]
        lines << "  [services.proxy]"
        lines << %(    enabled = #{svc["proxy"]["enabled"]})
        lines << %(    type = "#{svc["proxy"]["type"]}")
        svc["proxy"]["ports"]&.each do |port|
          lines << "    [[services.proxy.ports]]"
          lines << %(      host = #{port["host"]})
          lines << %(      container = #{port["container"]})
          lines << %(      scheme = "#{port["scheme"]}") if port["scheme"]
        end
      end

      if svc["storage"]
        svc["storage"].each do |st|
          lines << "    [[services.storage]]"
          lines << %(      host = "#{st["host"]}")
          lines << %(      container = "#{st["container"]}")
        end
      end

      if svc["checks"]
        lines << "  [services.checks]"
        lines << %(    enabled = #{svc["checks"]["enabled"]})
        lines << %(    wait = #{svc["checks"]["wait"]})
        lines << %(    timeout = #{svc["checks"]["timeout"]})
      end

      lines << ""
    end

    manifest["links"].each do |link|
      lines << "[[links]]"
      lines << %(from = "#{link["from"]}")
      lines << %(to = "#{link["to"]}")
      lines << ""
    end

    lines.join("\n")
  end

  def escape_toml_string(str)
    str.to_s.gsub('"', '\\"').gsub("\n", "\\n")
  end
end
