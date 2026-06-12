# frozen_string_literal: true

require "toml-rb"
require "json"

# Parses declarative configuration files (app.json, raildock.toml, raildock.json)
# into a normalized internal representation: ManifestDesiredState.
class ManifestParser
  class ParseError < StandardError; end

  # Result object holding the normalized desired state
  class ManifestDesiredState
    attr_reader :services, :links, :format_detected, :warnings, :raw

    def initialize(services: [], links: [], format_detected: nil, warnings: [], raw: nil)
      @services = services
      @links = links
      @format_detected = format_detected
      @warnings = warnings
      @raw = raw
    end

    def service_names
      @services.map { |s| s[:name] }
    end

    def find_service(name)
      @services.find { |s| s[:name] == name }
    end
  end

  # Resolves runtime variable markers inserted during manifest parsing.
  # Called after services and links are fully created, so project context
  # is available to fetch actual values for [RAILDOCK_*], [SHARED:*],
  # and [LINKED:*] markers.
  def self.resolve_runtime(env_value, project, service, linked_services)
    new.resolve_runtime(env_value, project, service, linked_services)
  end

  def resolve_runtime(env_value, project, service, linked_services)
    result = env_value.to_s.dup

    # ${{ RAILDOCK_PUBLIC_DOMAIN }} → this service's public domain
    # Handles raw ${{ }} syntax (for direct API calls) AND pre-parsed [MARKER] tags
    if result.include?("[RAILDOCK_PUBLIC_DOMAIN]") || result.include?("${{ RAILDOCK_PUBLIC_DOMAIN }}")
      domain = service&.domains&.reject { |d| d.hostname.to_s.include?(".localhost") || d.hostname == "localhost" }&.first&.hostname
      result = result.gsub("[RAILDOCK_PUBLIC_DOMAIN]", domain || "[RAILDOCK_PUBLIC_DOMAIN]")
      result = result.gsub("${{ RAILDOCK_PUBLIC_DOMAIN }}", domain || "[RAILDOCK_PUBLIC_DOMAIN]")
    end

    # ${{ shared.VAR }} → runtime resolved
    result = resolve_shared_vars(result, project) if result.include?("[SHARED:") || result.match?(/\$\{\{\s*shared\./)

    # ${{ linked.SERVICE.VAR }} → runtime resolved
    result = resolve_linked_vars(result, linked_services) if result.include?("[LINKED:") || result.match?(/\$\{\{\s*linked\./)

    result
  end

  # ── Public API ──────────────────────────────────────────────

  def self.parse(raw_content, filename: nil)
    new.parse(raw_content, filename: filename)
  end

  def parse(raw_content, filename: nil)
    @secret_cache = {}
    format = detect_format(raw_content, filename)
    hash = parse_raw(raw_content, format)
    normalize(hash, format, raw_content)
  rescue TomlRB::ParseError => e
    raise ParseError, "Invalid TOML: #{e.message}"
  rescue JSON::ParserError => e
    raise ParseError, "Invalid JSON: #{e.message}"
  end

  private

  # ── Format Detection ────────────────────────────────────────

  def detect_format(raw_content, filename)
    return :app_json if filename.to_s.downcase == "app.json"
    return :raildock_toml if filename.to_s.downcase == "raildock.toml"
    return :raildock_json if filename.to_s.downcase == "raildock.json"

    stripped = raw_content.to_s.strip
    return :app_json if stripped.start_with?("{") && stripped.include?("buildpacks") || stripped.include?("formation")
    return :raildock_toml if stripped.start_with?("[") || stripped.match?(/\A\s*name\s*=/)
    return :raildock_json if stripped.start_with?("{")

    :unknown
  end

  # ── Raw Parsing ─────────────────────────────────────────────

  def parse_raw(raw_content, format)
    case format
    when :app_json, :raildock_json
      JSON.parse(raw_content)
    when :raildock_toml
      TomlRB.parse(raw_content)
    else
      raise ParseError, "Unable to detect manifest format. Use app.json, raildock.toml, or raildock.json"
    end
  end

  # ── Normalization ───────────────────────────────────────────

  def normalize(hash, format, raw_content)
    case format
    when :app_json
      normalize_app_json(hash, raw_content)
    when :raildock_toml, :raildock_json
      normalize_raildock(hash, raw_content)
    else
      raise ParseError, "Unsupported manifest format: #{format}"
    end
  end

  # ── app.json (Heroku / Dokku native) ────────────────────────

  def normalize_app_json(hash, raw)
    warnings = []
    services = []
    links = []

    # app.json is single-service by nature (per Heroku app)
    # We wrap it as a single service in our multi-service model
    svc = {
      name: hash["name"] || "app",
      category: "app",
      subtype: detect_subtype_from_buildpacks(hash["buildpacks"]),
      builder: nil,
      source: { type: "git" },
      env: normalize_app_json_env(hash["env"]),
      domains: [],
      storage: [],
      proxy: { enabled: true, type: "traefik", ports: [ { host: 80, container: 3000 } ] },
      scaling: normalize_app_json_formation(hash["formation"]),
      limits: {},
      checks: normalize_app_json_healthchecks(hash["healthchecks"]),
      cron: normalize_app_json_cron(hash["cron"]),
      docker_options: [],
      traefik_labels: {},
      letsencrypt: { enabled: false },
      maintenance: false,
      scripts: {
        predeploy: hash.dig("scripts", "dokku", "predeploy"),
        postdeploy: hash.dig("scripts", "dokku", "postdeploy")
      }
    }

    services << svc

    warnings << "app.json does not support domains, storage, or proxy config. Use raildock.toml for full feature coverage."
    warnings << "app.json does not support service links. Use raildock.toml for multi-service stacks."

    ManifestDesiredState.new(
      services: services,
      links: links,
      format_detected: "app.json",
      warnings: warnings,
      raw: raw
    )
  end

  def normalize_app_json_env(env_hash)
    return {} unless env_hash.is_a?(Hash)
    result = {}
    env_hash.each do |key, val|
      case val
      when String
        result[key] = val
      when Hash
        if val["value"]
          result[key] = val["value"]
        elsif val["generator"]
          result[key] = "#{val["generator"].upcase}_GENERATED"
        end
      end
    end
    result
  end

  def normalize_app_json_formation(formation)
    return {} unless formation.is_a?(Hash)
    formation.transform_values do |v|
      v["quantity"].to_i
    end
  end

  def normalize_app_json_healthchecks(healthchecks)
    return { enabled: false } unless healthchecks.is_a?(Hash)
    web = healthchecks["web"] || healthchecks.values.first
    return { enabled: false } unless web.is_a?(Hash)

    {
      enabled: true,
      wait: web.dig("initialDelay", "value").to_i,
      timeout: web.dig("timeout", "value").to_i,
      skip: []
    }
  end

  def normalize_app_json_cron(cron_array)
    return [] unless cron_array.is_a?(Array)
    cron_array.map do |entry|
      {
        command: entry["command"],
        schedule: entry["schedule"]
      }
    end.compact
  end

  def detect_subtype_from_buildpacks(buildpacks)
    return nil unless buildpacks.is_a?(Array)
    urls = buildpacks.map { |b| b.is_a?(String) ? b : b["url"] }.join(" ").downcase
    case urls
    when /ruby|rails/ then "rails"
    when /node|nodejs/ then "node"
    when /python/ then "python"
    when /php/ then "php"
    when /go/ then "go"
    when /java/ then "java"
    else "web"
    end
  end

  # ── raildock.toml / raildock.json ───────────────────────────

  def normalize_raildock(hash, raw)
    warnings = []
    services = []
    links = []

    svc_list = hash["services"] || []
    unless svc_list.is_a?(Array)
      raise ParseError, "Manifest must have a 'services' array"
    end

    svc_list.each_with_index do |svc_hash, idx|
      svc = normalize_raildock_service(svc_hash, idx, warnings)
      services << svc
    end

    link_list = hash["links"] || []
    if link_list.is_a?(Array)
      link_list.each_with_index do |link_hash, idx|
        link = normalize_raildock_link(link_hash, idx, warnings)
        links << link if link
      end
    end

    ManifestDesiredState.new(
      services: services,
      links: links,
      format_detected: hash.key?("services") && raw.strip.start_with?("{") ? "raildock.json" : "raildock.toml",
      warnings: warnings,
      raw: raw
    )
  end

  def normalize_raildock_service(svc_hash, idx, warnings)
    name = svc_hash["name"] || svc_hash[:name]
    raise ParseError, "Service at index #{idx} is missing a 'name'" if name.blank?

    category = (svc_hash["category"] || svc_hash[:category] || "app").to_s
    category = "service" unless %w[app database cache queue search service].include?(category)

    source = normalize_source(svc_hash["source"] || svc_hash[:source])
    proxy = normalize_proxy(svc_hash["proxy"] || svc_hash[:proxy])
    scaling = normalize_scaling(svc_hash["scaling"] || svc_hash[:scaling])
    limits = normalize_limits(svc_hash["limits"] || svc_hash[:limits])
    checks = normalize_checks(svc_hash["checks"] || svc_hash[:checks])
    cron = normalize_cron(svc_hash["cron"] || svc_hash[:cron])
    storage = normalize_storage(svc_hash["storage"] || svc_hash[:storage])
    env = normalize_env(svc_hash["env"] || svc_hash[:env])
    docker_options = normalize_docker_options(svc_hash["docker_options"] || svc_hash[:docker_options])
    traefik_labels = normalize_traefik_labels(svc_hash["traefik_labels"] || svc_hash[:traefik_labels])
    letsencrypt = normalize_letsencrypt(svc_hash["letsencrypt"] || svc_hash[:letsencrypt])

{
      name: name.to_s,
      category: category,
      subtype: (svc_hash["subtype"] || svc_hash[:subtype] || "web").to_s,
      builder: svc_hash["builder"] || svc_hash[:builder],
      source: source,
      env: env,
      domains: normalize_domains(svc_hash["domains"] || svc_hash[:domains]),
      storage: storage,
      proxy: proxy,
      scaling: scaling,
      limits: limits,
      checks: checks,
      cron: cron,
      docker_options: docker_options,
      traefik_labels: normalize_traefik_labels(svc_hash["traefik_labels"] || svc_hash[:traefik_labels]),
      letsencrypt: normalize_letsencrypt(svc_hash["letsencrypt"] || svc_hash[:letsencrypt]),
      maintenance: svc_hash["maintenance"] || svc_hash[:maintenance] || false,
      version: svc_hash["version"] || svc_hash[:version],
      docker_image: svc_hash["docker_image"] || svc_hash[:docker_image],
      start_command: svc_hash["start_command"] || svc_hash[:start_command],
      exposed: svc_hash["exposed"] || svc_hash[:exposed],
      depends_on: normalize_depends_on(svc_hash["depends_on"] || svc_hash[:depends_on])
    }
  end

  def normalize_source(source)
    return { type: "git" } unless source.is_a?(Hash)
    {
      type: source["type"] || source[:type] || "git",
      repo: source["repo"] || source[:repo],
      branch: source["branch"] || source[:branch] || "main"
    }
  end

  def normalize_proxy(proxy)
    defaults = { enabled: true, type: "traefik", ports: [ { host: 80, container: 3000 } ] }
    return defaults unless proxy.is_a?(Hash)

    ports = (proxy["ports"] || proxy[:ports] || []).map do |p|
      {
        host: (p["host"] || p[:host] || 80).to_i,
        container: (p["container"] || p[:container] || 3000).to_i,
        scheme: (p["scheme"] || p[:scheme] || "http").to_s
      }
    end
    ports = defaults[:ports] if ports.empty?

    {
      enabled: proxy["enabled"] != false && proxy[:enabled] != false,
      type: (proxy["type"] || proxy[:type] || "traefik").to_s,
      ports: ports
    }
  end

  def normalize_domains(domains)
    return [] unless domains.is_a?(Array)
    domains.map { |d| d.is_a?(String) ? d : d["hostname"] || d[:hostname] }.compact
  end

  def normalize_storage(storage)
    return [] unless storage.is_a?(Array)
    storage.map do |s|
      next unless s.is_a?(Hash)
      {
        host: (s["host"] || s[:host]).to_s,
        container: (s["container"] || s[:container]).to_s
      }
    end.compact
  end

  def normalize_scaling(scaling)
    return {} unless scaling.is_a?(Hash)
    result = {}
    scaling.each do |k, v|
      result[k.to_s] = v.to_i
    end
    result
  end

  def normalize_limits(limits)
    return {} unless limits.is_a?(Hash)
    result = {}
    limits.each do |process_type, cfg|
      next unless cfg.is_a?(Hash)
      result[process_type.to_s] = {
        memory: cfg["memory"] || cfg[:memory],
        cpu: cfg["cpu"] || cfg[:cpu],
        nvidia_gpu: cfg["nvidia_gpu"] || cfg[:nvidia_gpu]
      }.compact
    end
    result
  end

  def normalize_checks(checks)
    defaults = { enabled: true, wait: 5, timeout: 30, skip: [] }
    return defaults unless checks.is_a?(Hash)
    {
      enabled: checks["enabled"] != false && checks[:enabled] != false,
      wait: (checks["wait"] || checks[:wait] || 5).to_i,
      timeout: (checks["timeout"] || checks[:timeout] || 30).to_i,
      skip: Array(checks["skip"] || checks[:skip] || [])
    }
  end

  def normalize_cron(cron)
    return [] unless cron.is_a?(Array)
    cron.map do |c|
      next unless c.is_a?(Hash)
      {
        command: (c["command"] || c[:command]).to_s,
        schedule: (c["schedule"] || c[:schedule]).to_s
      }
    end.compact
  end

  def normalize_docker_options(opts)
    return [] unless opts.is_a?(Array)
    opts.map do |o|
      next unless o.is_a?(Hash)
      {
        phase: (o["phase"] || o[:phase] || "deploy").to_s,
        option: (o["option"] || o[:option]).to_s
      }
    end.compact
  end

  def normalize_traefik_labels(labels)
    return {} unless labels.is_a?(Hash)
    labels.transform_keys(&:to_s).transform_values(&:to_s)
  end

  def normalize_letsencrypt(le)
    defaults = { enabled: false, email: nil, staging: false, auto_renew: true }
    return defaults unless le.is_a?(Hash)
    {
      enabled: le["enabled"] == true || le[:enabled] == true,
      email: le["email"] || le[:email],
      staging: le["staging"] == true || le[:staging] == true,
      auto_renew: le["auto_renew"] != false && le[:auto_renew] != false
    }
  end

  def normalize_depends_on(deps)
    return [] unless deps
    Array(deps).map(&:to_s)
  end

def normalize_env(env)
    return {} unless env.is_a?(Hash)
    env.transform_keys(&:to_s).transform_values { |v| resolve_placeholders(v.to_s) }
  end

  def resolve_placeholders(value)
    return value unless value.is_a?(String)

    result = value.dup

    # Cache for inline secret() calls to return the same value within one parse
    @secret_cache ||= {}

    # ── Coolify-style legacy placeholders ─────────────────────

    result.gsub!(/\$\{?SERVICE_PASSWORD(?:_64)?_[A-Z0-9_]+\}?/) { SecureRandom.hex(16) }
    result.gsub!(/\$\{?SERVICE_USER_[A-Z0-9_]+\}?/) { "user" }
    result.gsub!(/\$\{?SERVICE_URL_[A-Z0-9_]+\}?/) { "https://example.com" }
    result.gsub!(/\$\{?SERVICE_FQDN_[A-Z0-9_]+\}?/) { "app.example.com" }
    result.gsub!(/\$\{?SERVICE_BASE64(?:_64|_32)?_[A-Z0-9_]+\}?/) { SecureRandom.base64(32) }
    result.gsub!(/\$\{?SERVICE_PASSWORD\}?/) { SecureRandom.hex(16) }
    result.gsub!(/\$\{?SERVICE_USER\}?/) { "user" }
    result.gsub!(/\$\{?SERVICE_URL\}?/) { "https://example.com" }
    result.gsub!(/\$\{?SERVICE_FQDN\}?/) { "app.example.com" }
    result.gsub!(/CHANGE_ME/) { SecureRandom.hex(16) }

    # ── Railway-style ${{ }} expressions ───────────────────────

    # ${{ secret() }} → 32-char hex, ${{ secret(N) }} → N-char hex (cached per call site)
    result.gsub!(/\$\{\{\s*secret\(\s*(\d+)?\s*\)\s*\}\}/) do
      length = ($1 || "32").to_i
      length = [ 1, [ length, 128 ].min ].max
      cache_key = "secret_#{length}"
      @secret_cache[cache_key] ||= SecureRandom.hex(length / 2)
    end

    # ${{ randomInt(min, max) }}
    result.gsub!(/\$\{\{\s*randomInt\(\s*(\d+)\s*,\s*(\d+)\s*\)\s*\}\}/) do
      min = $1.to_i
      max = $2.to_i
      min = [ min, max ].min
      max = [ min, max ].max
      rand(min..max).to_s
    end

    # ${{ RAILDOCK_PUBLIC_DOMAIN }} → runtime resolved (placeholder tag for now)
    result.gsub!(/\$\{\{\s*RAILDOCK_PUBLIC_DOMAIN\s*\}\}/) { "[RAILDOCK_PUBLIC_DOMAIN]" }

    # ${{ shared.VAR }} → runtime resolved (placeholder tag)
    result.gsub!(/\$\{\{\s*shared\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}/) do
      "[SHARED:#{$1}]"
    end

    # ${{ linked.SERVICE.VAR }} → runtime resolved (placeholder tag)
    result.gsub!(/\$\{\{\s*linked\.([A-Za-z][A-Za-z0-9_-]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}/) do
      "[LINKED:#{$1}:#{$2}]"
    end

    result
  end

  # Resolve Coolify-style placeholders AND Railway-style ${{ }} expressions.
  # $SERVICE_PASSWORD_XXX  → random hex password (Coolify legacy)
  # $SERVICE_USER_XXX      → "user" (Coolify legacy)
  # $SERVICE_URL_XXX       → "https://example.com" (Coolify legacy)
  # $SERVICE_BASE64_XXX    → base64 random string (Coolify legacy)
  # CHANGE_ME              → random hex (Coolify legacy)
  # ${{ secret() }}        → 32-char random hex (Railway-style)
  # ${{ secret(N) }}       → N-char random hex
  # ${{ randomInt(min,max) }} → random integer
  # ${{ RAILDOCK_PUBLIC_DOMAIN }} → "[REQUIRES_DEPLOY]" (runtime)
  # ${{ shared.VAR }}      → "[REQUIRES_SHARED:VAR]" (runtime)
  # ${{ linked.SERVICE.VAR }} → "[REQUIRES_LINKED:SERVICE:VAR]" (runtime)
  def resolve_placeholders(value)
    return value unless value.is_a?(String)

    result = value.dup

    # ── Coolify-style legacy placeholders ─────────────────────

    result.gsub!(/\$\{?SERVICE_PASSWORD(?:_64)?_[A-Z0-9_]+\}?/) { SecureRandom.hex(16) }
    result.gsub!(/\$\{?SERVICE_USER_[A-Z0-9_]+\}?/) { "user" }
    result.gsub!(/\$\{?SERVICE_URL_[A-Z0-9_]+\}?/) { "https://example.com" }
    result.gsub!(/\$\{?SERVICE_FQDN_[A-Z0-9_]+\}?/) { "app.example.com" }
    result.gsub!(/\$\{?SERVICE_BASE64(?:_64|_32)?_[A-Z0-9_]+\}?/) { SecureRandom.base64(32) }
    result.gsub!(/\$\{?SERVICE_PASSWORD\}?/) { SecureRandom.hex(16) }
    result.gsub!(/\$\{?SERVICE_USER\}?/) { "user" }
    result.gsub!(/\$\{?SERVICE_URL\}?/) { "https://example.com" }
    result.gsub!(/\$\{?SERVICE_FQDN\}?/) { "app.example.com" }
    result.gsub!(/CHANGE_ME/) { SecureRandom.hex(16) }

    # ── Railway-style ${{ }} expressions ───────────────────────

    # ${{ secret() }} → 32-char hex, ${{ secret(N) }} → N-char hex
    result.gsub!(/\$\{\{\s*secret\(\s*(\d+)?\s*\)\s*\}\}/) do
      length = ($1 || "32").to_i
      length = [ 1, [ length, 128 ].min ].max
      SecureRandom.hex(length / 2)
    end

    # ${{ randomInt(min, max) }}
    result.gsub!(/\$\{\{\s*randomInt\(\s*(\d+)\s*,\s*(\d+)\s*\)\s*\}\}/) do
      min = $1.to_i
      max = $2.to_i
      min = [ min, max ].min
      max = [ min, max ].max
      rand(min..max).to_s
    end

    # ${{ RAILDOCK_PUBLIC_DOMAIN }} → runtime resolved (placeholder tag for now)
    result.gsub!(/\$\{\{\s*RAILDOCK_PUBLIC_DOMAIN\s*\}\}/) { "[RAILDOCK_PUBLIC_DOMAIN]" }

    # ${{ shared.VAR }} → runtime resolved (placeholder tag)
    result.gsub!(/\$\{\{\s*shared\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}/) do
      "[SHARED:#{$1}]"
    end

    # ${{ linked.SERVICE.VAR }} → runtime resolved (placeholder tag)
    result.gsub!(/\$\{\{\s*linked\.([A-Za-z][A-Za-z0-9_-]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}/) do
      "[LINKED:#{$1}:#{$2}]"
    end

    result
  end

  def normalize_raildock_link(link_hash, idx, warnings)
    from = link_hash["from"] || link_hash[:from]
    to = link_hash["to"] || link_hash[:to]
    if from.blank? || to.blank?
      warnings << "Link at index #{idx} missing 'from' or 'to' — skipped"
      return nil
    end
    {
      from: from.to_s,
      to: to.to_s,
      alias: (link_hash["alias"] || link_hash[:alias]).to_s
    }
  end

  # ── Runtime variable resolution helpers ──────────────────────

  def fetch_public_domain(project)
    return nil unless project&.server&.ssh_key.present?

    engine = DokkuEngine.new(project.server)
    result = engine.run("domains:report #{engine.escape(project.server.dokku_app_name)} --domains-app-vhosts")
    return nil unless result[:success]

    domains = result[:output].to_s.strip.split
    domains.reject { |d| d.include?(".localhost") || d == "localhost" }.first
  rescue => e
    Rails.logger.warn "Failed to fetch public domain: #{e.message}"
    nil
  end

  def resolve_shared_vars(value, project)
    return value unless value.include?("[SHARED:") || value.match?(/\$\{\{\s*shared\./)

    result = value.dup
    # Handle pre-parsed [SHARED:X] markers
    result.gsub!(/\[SHARED:([A-Za-z_][A-Za-z0-9_]*)\]/) do
      var_name = $1
      if project && project.respond_to?(:project_variables)
        shared_var = project.project_variables.find_by(key: var_name)
        shared_var&.value || "[SHARED:#{var_name}]"
      else
        "[SHARED:#{var_name}]"
      end
    end
    # Handle raw ${{ shared.VAR }} syntax
    result.gsub!(/\$\{\{\s*shared\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}/) do
      var_name = $1
      if project && project.respond_to?(:project_variables)
        shared_var = project.project_variables.find_by(key: var_name)
        shared_var&.value || "[SHARED:#{var_name}]"
      else
        "[SHARED:#{var_name}]"
      end
    end
    result
  end

  def resolve_linked_vars(value, linked_services)
    return value unless value.include?("[LINKED:") || value.match?(/\$\{\{\s*linked\./)

    result = value.dup
    # Handle pre-parsed [LINKED:svc:var] markers
    result.gsub!(/\[LINKED:([A-Za-z][A-Za-z0-9_-]*):([A-Za-z_][A-Za-z0-9_]*)\]/) do
      svc_name = $1
      var_name = $2
      linked_svc = linked_services.find { |s| s.name == svc_name }
      unless linked_svc
        Rails.logger.warn "Linked service '#{svc_name}' not found"
        next "[LINKED:#{svc_name}:#{var_name}]"
      end
      env_vars = linked_svc.environment_variables
      env_vars = env_vars.to_a if env_vars.is_a?(ActiveRecord::Associations::CollectionProxy)
      ev = env_vars.find { |e| e.key == var_name }
      unless ev
        Rails.logger.warn "Variable '#{var_name}' not found on linked service '#{svc_name}'"
        next "[LINKED:#{svc_name}:#{var_name}]"
      end
      ev.value
    end
    # Handle raw ${{ linked.svc.VAR }} syntax
    result.gsub!(/\$\{\{\s*linked\.([A-Za-z][A-Za-z0-9_-]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}/) do
      svc_name = $1
      var_name = $2
      linked_svc = linked_services.find { |s| s.name == svc_name }
      unless linked_svc
        Rails.logger.warn "Linked service '#{svc_name}' not found for ${{ linked.#{svc_name}.#{var_name} }}"
        next "[LINKED:#{svc_name}:#{var_name}]"
      end
      env_vars = linked_svc.environment_variables
      env_vars = env_vars.to_a if env_vars.is_a?(ActiveRecord::Associations::CollectionProxy)
      ev = env_vars.find { |e| e.key == var_name }
      unless ev
        Rails.logger.warn "Variable '#{var_name}' not found on linked service '#{svc_name}'"
        next "[LINKED:#{svc_name}:#{var_name}]"
      end
      ev.value
    end
    result
  end
end
