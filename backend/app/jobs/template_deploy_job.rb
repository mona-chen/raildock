# frozen_string_literal: true

# Applies a one-click template to a project in the background.
#
# TemplatesController#deploy creates the project and service records, then
# enqueues this job. The job does the Dokku-side setup (apps, datastores,
# links, networks) and finally enqueues DeploymentJob for each app service.
# Keeping the SSH work out of the request prevents nginx 60s timeouts and
# lets the UI poll deployment status instead.
class TemplateDeployJob < ApplicationJob
  queue_as :default

  PASSWORD_VAR_NAMES = %w[
    POSTGRES_PASSWORD POSTGRES_DB_PASSWORD POSTGRES_USER_PASSWORD
    MYSQL_ROOT_PASSWORD MYSQL_PASSWORD MARIADB_ROOT_PASSWORD MARIADB_PASSWORD
    REDIS_PASSWORD MONGO_PASSWORD MONGODB_PASSWORD
    DB_PASSWORD DATABASE_PASSWORD DB_PASS
    PASSWORD SECRET SECRET_KEY SECRET_KEY_BASE
    ENCRYPTION_KEY ENCRYPTION_KEY_BASE
    ADMIN_TOKEN ADMIN_PASSWORD APP_SECRET SESSION_SECRET
    AUTH_SECRET AUTH_TOKEN API_SECRET API_KEY
  ].freeze

  def perform(project_id, template_id)
    project = Project.find_by(id: project_id)
    return unless project

    template = TemplateLoader.find(template_id)
    return unless template

    server = project.server
    return unless server&.ssh_key.present?

    engine = DokkuEngine.new(server)

    engine.with_session do
      HostEngine.new(server).with_session do
        apply_dokku_resources(project, template, engine)
        create_links(project, template, engine)
        connect_networks(project, engine)
        resolve_runtime_values(project, engine)
        enqueue_app_deployments(project)
      end
    end
  rescue => e
    Rails.logger.error "TemplateDeployJob failed for project #{project_id}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
    broadcast_error(project_id, e.message)
  end

  private

  def apply_dokku_resources(project, template, engine)
    project.services.each do |service|
      app_name = service.dokku_app_name

      if service.service_type_database?
        case service.subtype
        when "postgres" then engine.postgres_create(app_name)
        when "redis" then engine.redis_create(app_name)
        when "mysql", "mariadb" then engine.mysql_create(app_name)
        when "mongo" then engine.mongo_create(app_name)
        end
      else
        engine.app_create(app_name)
        proxy_type = service.config&.dig("proxy", "type") || "traefik"
        engine.proxy_set(app_name, proxy_type)

        # Auto-provision a temporary domain for web services when the server
        # has auto_domains enabled. This must happen before runtime env vars
        # like RAILDOCK_PUBLIC_DOMAIN are resolved.
        TemporaryDomainService.new(project.server).ensure_for(service, engine: engine)
      end

      # Sync storage mounts
      service.storage_mounts.each do |mount|
        engine.storage_mount(app_name, mount.host_path, mount.container_path)
      end
    end
  end

  def create_links(project, template, engine)
    template.links.each do |link|
      from_svc = project.services.find_by(name: link[:from])
      to_svc = project.services.find_by(name: link[:to])
      next unless from_svc && to_svc

      ServiceLink.find_or_create_by!(from_service: from_svc, to_service: to_svc)

      if to_svc.docker_image_database?
        link_result = engine.send("#{to_svc.subtype}_link", to_svc.dokku_app_name, from_svc.dokku_app_name)
        unless link_result[:success]
          Rails.logger.error "Dokku link failed for #{link[:from]} -> #{link[:to]}: #{link_result[:output]}"
          next
        end

        sync_dokku_env_vars(engine, from_svc)
        set_canonical_db_url(engine, from_svc, to_svc)
        if to_svc.subtype == "postgres"
          engine.config_set(from_svc.dokku_app_name, "PGSSLMODE", "disable")
          from_svc.environment_variables.find_or_initialize_by(key: "PGSSLMODE").update!(value: "disable")
        end
      end
    end
  end

  def connect_networks(project, engine)
    network_manager = ProjectNetworkManager.new(project, engine)
    project.services.each do |service|
      service.reload
      network_manager.connect_service(service)
    rescue => e
      Rails.logger.warn "Network connect failed for #{service.dokku_app_name}: #{e.message}"
    end
  end

  def resolve_runtime_values(project, engine)
    app_services = project.services.select(&:service_type_app?)

    # Resolve runtime variable markers
    app_services.each do |service|
      service.environment_variables.each do |ev|
        next unless ev.value.to_s.include?("[")
        resolved = ManifestParser.resolve_runtime(ev.value, project, service, service.linked_services)
        next if resolved == ev.value

        engine.config_set(service.dokku_app_name, ev.key, resolved)
        ev.update!(value: resolved)
        Rails.logger.info "Resolved runtime markers in #{ev.key} on #{service.dokku_app_name}"
      end
    end

    # Rewrite connection URL env vars to use actual linked credentials
    app_services.each do |service|
      linked_dbs = service.linked_services.select(&:service_type_database?)
      next if linked_dbs.empty?

      db_url_map = {
        "postgres" => [ "DATABASE_URL", /\Apostgres(?:ql)?:\/\//i ],
        "redis"    => [ "REDIS_URL",    /\Aredis:\/\//i ],
        "mysql"    => [ "DATABASE_URL", /\Amysql:\/\//i ],
        "mariadb"  => [ "DATABASE_URL", /\Amysql:\/\//i ],
        "mongo"    => [ "MONGO_URL",    /\Amongodb(?:\+srv)?:\/\//i ]
      }.freeze

      linked_dbs.each do |db|
        mapping = db_url_map[db.subtype]
        next unless mapping

        url_var, url_pattern = mapping
        actual_ev = service.environment_variables.find_by(key: url_var)
        next unless actual_ev

        actual_url = actual_ev.value
        next if actual_url.blank?

        service.environment_variables.where.not(key: url_var).each do |ev|
          next unless ev.value.match?(url_pattern)

          engine.config_set(service.dokku_app_name, ev.key, actual_url)
          ev.update!(value: actual_url)
          Rails.logger.info "Rewrote #{ev.key} on #{service.dokku_app_name} to use actual #{db.subtype} credentials from #{url_var}"
        end
      end
    end
  end

  def enqueue_app_deployments(project)
    app_services = project.services.select(&:service_type_app?)
    sorted = topo_sort_by_depends_on(app_services)

    sorted.each do |service|
      deployment = service.deployments.create!(
        status: :pending,
        started_at: Time.current,
        branch: service.branch || "main"
      )
      DeploymentJob.perform_later(service.id, deployment.id)
      service.update!(status: :deploying)

      ActivityEvent.create!(
        project: project,
        service_name: service.name,
        action: :deployed,
        message: "Template deploy triggered for #{service.name}"
      )
    end
  end

  def topo_sort_by_depends_on(services)
    svc_map = services.map { |s| [ s.name, s ] }.to_h
    in_degree = Hash.new(0)
    dependents = Hash.new { |h, k| h[k] = [] }

    services.each do |svc|
      deps = svc.config&.dig("depends_on") || []
      in_degree[svc.name] += 0
      deps.each do |dep|
        if svc_map.key?(dep)
          dependents[dep] << svc.name
          in_degree[svc.name] += 1
        end
      end
    end

    queue = services.select { |s| in_degree[s.name] == 0 }
    sorted = []
    while queue.any?
      svc = queue.shift
      sorted << svc
      dependents[svc.name].each do |dep|
        in_degree[dep] -= 1
        queue << svc_map[dep] if in_degree[dep] == 0
      end
    end
    sorted + services.reject { |s| sorted.include?(s) }
  end

  def set_canonical_db_url(engine, app_service, db_service)
    info_method = "#{db_service.subtype}_info"
    return unless engine.respond_to?(info_method)

    info = engine.send(info_method, db_service.dokku_app_name)
    return unless info[:success] && info[:dsn].present?

    dsn = info[:dsn]
    target_key = case db_service.subtype
    when "postgres" then "DATABASE_URL"
    when "mysql", "mariadb" then "DATABASE_URL"
    when "redis" then "REDIS_URL"
    when "mongo" then "MONGO_URL"
    else nil
    end

    return unless target_key

    engine.config_set(app_service.dokku_app_name, target_key, dsn)
    ev = app_service.environment_variables.find_or_initialize_by(key: target_key)
    ev.update!(value: dsn, source: "dokku-link")
    Rails.logger.info "Set #{target_key} on #{app_service.dokku_app_name} to linked #{db_service.subtype} DSN"
  rescue => e
    Rails.logger.warn "Failed to set canonical DB URL for #{app_service.dokku_app_name}: #{e.message}"
  end

  def sync_dokku_env_vars(engine, service)
    result = engine.config_show(service.dokku_app_name)
    return unless result[:success]

    result[:output].each_line do |line|
      line = line.strip
      next unless line.include?("=")
      key, _, value = line.partition("=")
      key = key.strip
      value = value.strip
      next unless key.match?(/^(DATABASE_URL|REDIS_URL|MONGO_URL|MYSQL_URL|DATABASE_PRIVATE_URL|REDIS_PRIVATE_URL|DOKKU_MYSQL|DOKKU_POSTGRES|DOKKU_REDIS|DOKKU_MONGO)/i)
      next if value.blank? || value.start_with?("$")

      existing = service.environment_variables.find_by(key: key)
      if existing
        existing.update!(value: value) if existing.value != value
      else
        service.environment_variables.create!(key: key, value: value, source: "dokku-link")
      end
    end
  rescue => e
    Rails.logger.warn "Failed to sync Dokku env vars for #{service.dokku_app_name}: #{e.message}"
  end

  def broadcast_error(project_id, message)
    ActionCable.server.broadcast("project_#{project_id}", {
      type: "template_deploy",
      status: "failed",
      message: message,
      timestamp: Time.current.iso8601
    })
  end
end
