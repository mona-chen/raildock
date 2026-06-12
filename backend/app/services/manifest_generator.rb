# frozen_string_literal: true

# Generates a raildock.toml manifest from a project's actual state.
# This is the inverse of ManifestParser — it walks the database and produces
# a declarative manifest that, if parsed and reconciled, would result in the
# same infrastructure.
#
# Usage:
#   ManifestGenerator.new(project).generate
class ManifestGenerator
  def initialize(project)
    @project = project
  end

  def generate(format: :toml)
    desired = build_desired_state
    case format
    when :toml then to_toml(desired)
    when :json then to_json(desired)
    else to_toml(desired)
    end
  end

  private

  def build_desired_state
    services = @project.services.includes(
      :environment_variables, :domains, :storage_mounts, :process_types, :outgoing_links
    ).map { |svc| service_to_hash(svc) }

    links = @project.services.includes(:linked_services).flat_map do |svc|
      svc.linked_services.map do |target|
        { from: svc.name, to: target.name }
      end
    end

    { services: services, links: links }
  end

  def service_to_hash(svc)
    h = {
      name: svc.name,
      category: svc.service_type,
      subtype: svc.subtype
    }

    h[:builder] = svc.builder if svc.builder.present?
    h[:version] = svc.version if svc.version.present?
    h[:docker_image] = svc.docker_image if svc.docker_image.present?
    h[:start_command] = svc.start_command if svc.start_command.present?
    h[:root_directory] = svc.root_directory if svc.root_directory.present?
    h[:exposed] = svc.exposed unless svc.exposed.nil?
    h[:port] = svc.port if svc.port.present?
    h[:maintenance] = svc.maintenance_mode if svc.maintenance_mode

    # Source
    if svc.git_repo.present?
      h[:source] = { type: "git", repo: svc.git_repo, branch: svc.branch || "main" }
    elsif svc.docker_image.present?
      h[:source] = { type: "docker" }
    end

    # Env vars (skip dokku-internal link vars)
    user_env = svc.environment_variables.reject(&:is_dokku_internal)
    if user_env.any?
      h[:env] = user_env.map { |ev| [ ev.key, ev.value ] }.to_h
    end

    # Domains
    if svc.domains.any?
      h[:domains] = svc.domains.map(&:hostname)
    end

    # Storage
    if svc.storage_mounts.any?
      h[:storage] = svc.storage_mounts.map do |sm|
        { host: sm.host_path, container: sm.container_path }
      end
    end

    # Proxy
    proxy = svc.config&.dig("proxy")
    if proxy.present?
      h[:proxy] = {
        enabled: proxy["enabled"] != false,
        type: proxy["proxyType"] || proxy["type"] || "traefik"
      }
      ports = proxy["portMappings"] || proxy["ports"] || []
      if ports.any?
        h[:proxy][:ports] = ports.map do |p|
          { host: p["hostPort"] || p["host"], container: p["containerPort"] || p["container"], scheme: p["scheme"] || "http" }
        end
      end
    end

    # Scaling
    if svc.process_types.any?
      h[:scaling] = svc.process_types.map { |pt| [ pt.name, pt.quantity ] }.to_h
    end

    # Resource limits
    limits = svc.config&.dig("resourceLimits")
    if limits.present?
      h[:limits] = limits.transform_values do |cfg|
        cfg.slice("memory", "cpu", "nvidia_gpu").compact
      end
    end

    # Resource reservations
    reservations = svc.config&.dig("resourceReservations")
    if reservations.present?
      h[:reservations] = reservations.transform_values do |cfg|
        cfg.slice("memory", "cpu", "nvidia_gpu").compact
      end
    end

    # Health checks
    checks = svc.config&.dig("checks")
    if checks.present?
      h[:checks] = {
        enabled: checks["enabled"] != false,
        wait: checks["wait"] || 5,
        timeout: checks["timeout"] || 30,
        skip: checks["skipList"] || checks["skip"] || []
      }
    end

    # Cron
    cron = svc.config&.dig("cron")
    if cron.present?
      h[:cron] = cron.map do |c|
        { command: c["command"], schedule: c["schedule"] }
      end
    end

    # Docker options
    docker_opts = svc.config&.dig("dockerOptions")
    if docker_opts.present?
      h[:docker_options] = docker_opts.map do |o|
        { phase: o["phase"], option: o["option"] }
      end
    end

    # Traefik labels
    traefik = svc.config&.dig("traefik")
    if traefik.present? && traefik.is_a?(Hash) && traefik.keys.any?
      h[:traefik_labels] = traefik
    end

    # Let's Encrypt
    le = svc.config&.dig("letsencrypt")
    if le.present?
      h[:letsencrypt] = {
        enabled: le["enabled"] == true,
        email: le["email"],
        staging: le["staging"] == true,
        auto_renew: le["autoRenew"] != false
      }.compact
    end

    h
  end

  def to_toml(desired)
    lines = []
    lines << "# RailDock Manifest for #{@project.name}"
    lines << "# Generated from project state"
    lines << ""

    desired[:services].each do |svc|
      lines << "[[services]]"
      lines << "name = #{quote(svc[:name])}"
      lines << "category = #{quote(svc[:category])}"
      lines << "subtype = #{quote(svc[:subtype])}"
      lines << "builder = #{quote(svc[:builder])}" if svc[:builder]
      lines << "version = #{quote(svc[:version])}" if svc[:version]
      lines << "docker_image = #{quote(svc[:docker_image])}" if svc[:docker_image]
      lines << "start_command = #{quote(svc[:start_command])}" if svc[:start_command]
      lines << "root_directory = #{quote(svc[:root_directory])}" if svc[:root_directory]
      lines << "exposed = #{svc[:exposed]}" unless svc[:exposed].nil?
      lines << "port = #{svc[:port]}" if svc[:port]
      lines << "maintenance = #{svc[:maintenance]}" if svc[:maintenance]

      if svc[:source]
        if svc[:source][:repo]
          lines << "source = { type = #{quote(svc[:source][:type])}, repo = #{quote(svc[:source][:repo])}, branch = #{quote(svc[:source][:branch])} }"
        else
          lines << "source = { type = #{quote(svc[:source][:type])} }"
        end
      end

      if svc[:domains]
        lines << ""
        lines << "  domains = [#{svc[:domains].map { |d| quote(d) }.join(', ')}]"
      end

      if svc[:env]
        lines << ""
        lines << "  [services.env]"
        svc[:env].each do |k, v|
          lines << "  #{k} = #{quote(v)}"
        end
      end

      if svc[:storage]
        lines << ""
        svc[:storage].each do |mount|
          lines << "  [[services.storage]]"
          lines << "  host = #{quote(mount[:host])}"
          lines << "  container = #{quote(mount[:container])}"
        end
      end

      if svc[:proxy]
        lines << ""
        lines << "  [services.proxy]"
        lines << "  enabled = #{svc[:proxy][:enabled]}"
        lines << "  type = #{quote(svc[:proxy][:type])}"
        if svc[:proxy][:ports]
          svc[:proxy][:ports].each do |p|
            lines << ""
            lines << "    [[services.proxy.ports]]"
            lines << "    host = #{p[:host]}"
            lines << "    container = #{p[:container]}"
            lines << "    scheme = #{quote(p[:scheme])}"
          end
        end
      end

      if svc[:scaling]
        lines << ""
        lines << "  [services.scaling]"
        svc[:scaling].each do |k, v|
          lines << "  #{k} = #{v}"
        end
      end

      if svc[:limits]
        lines << ""
        lines << "  [services.limits]"
        svc[:limits].each do |process_type, cfg|
          lines << "  #{process_type} = { #{cfg.map { |k, v| "#{k} = #{quote(v)}" }.join(', ')} }"
        end
      end

      if svc[:reservations]
        lines << ""
        lines << "  [services.reservations]"
        svc[:reservations].each do |process_type, cfg|
          lines << "  #{process_type} = { #{cfg.map { |k, v| "#{k} = #{quote(v)}" }.join(', ')} }"
        end
      end

      if svc[:checks]
        lines << ""
        lines << "  [services.checks]"
        lines << "  enabled = #{svc[:checks][:enabled]}"
        lines << "  wait = #{svc[:checks][:wait]}"
        lines << "  timeout = #{svc[:checks][:timeout]}"
        if svc[:checks][:skip].any?
          lines << "  skip = [#{svc[:checks][:skip].map { |s| quote(s) }.join(', ')}]"
        end
      end

      if svc[:cron]
        lines << ""
        svc[:cron].each do |c|
          lines << "  [[services.cron]]"
          lines << "  command = #{quote(c[:command])}"
          lines << "  schedule = #{quote(c[:schedule])}"
        end
      end

      if svc[:docker_options]
        lines << ""
        svc[:docker_options].each do |o|
          lines << "  [[services.docker_options]]"
          lines << "  phase = #{quote(o[:phase])}"
          lines << "  option = #{quote(o[:option])}"
        end
      end

      if svc[:traefik_labels]
        lines << ""
        lines << "  [services.traefik_labels]"
        svc[:traefik_labels].each do |k, v|
          lines << "  #{k} = #{quote(v)}"
        end
      end

      if svc[:letsencrypt]
        lines << ""
        lines << "  [services.letsencrypt]"
        svc[:letsencrypt].each do |k, v|
          lines << "  #{k} = #{v.is_a?(String) ? quote(v) : v}"
        end
      end

      lines << ""
    end

    desired[:links].each do |link|
      lines << "[[links]]"
      lines << "from = #{quote(link[:from])}"
      lines << "to = #{quote(link[:to])}"
      lines << ""
    end

    lines.join("\n")
  end

  def to_json(desired)
    JSON.pretty_generate(desired)
  end

  def quote(str)
    return str if str.is_a?(Numeric) || str == true || str == false
    %("#{str.to_s.gsub('"', '\\"')}")
  end
end
