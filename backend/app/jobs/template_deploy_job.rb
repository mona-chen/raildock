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

  def perform(project_id, template_id, service_ids = nil, deployment_ids_by_service = nil)
    project = Project.find_by(id: project_id)
    return unless project

    template = TemplateLoader.find(template_id)
    return fail_pending_deployments(project, service_ids, deployment_ids_by_service, "Template not found") unless template

    server = project.server
    return fail_pending_deployments(project, service_ids, deployment_ids_by_service, "No server SSH key configured") unless server&.ssh_key.present?

    engine = DokkuEngine.new(server)
    services = scoped_services(project, service_ids)

    engine.with_session do
      HostEngine.new(server).with_session do
        apply_dokku_resources(project, template, engine, services)
        create_links(project, template, engine, services)
        connect_networks(project, engine, services)
        resolve_runtime_values(project, engine, services)
        enqueue_app_deployments(project, services, deployment_ids_by_service)
      end
    end
  rescue => e
    Rails.logger.error "TemplateDeployJob failed for project #{project_id}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
    fail_pending_deployments(project, service_ids, deployment_ids_by_service, e.message) if project
    broadcast_error(project_id, e.message)
  end

  private

  def apply_dokku_resources(project, template, engine, services)
    services.each do |service|
      app_name = service.dokku_app_name

      if service.service_type_database?
        result = case service.subtype
        when "postgres" then engine.postgres_create(app_name)
        when "redis" then engine.redis_create(app_name)
        when "mysql", "mariadb" then engine.mysql_create(app_name)
        when "mongo" then engine.mongo_create(app_name)
        else { success: false, output: "Unsupported database subtype: #{service.subtype}" }
        end
        ensure_success!(result, "create database #{app_name}")
      else
        ensure_success!(engine.app_create(app_name), "create app #{app_name}")
        unless project.server.external_proxy?
          proxy_type = service.config&.dig("proxy", "type") || "traefik"
          proxy_result = engine.proxy_set(app_name, proxy_type)
          ensure_success!(proxy_result, "configure proxy for #{app_name}")
        end

        # Auto-provision a temporary domain for web services when the server
        # has auto_domains enabled. This must happen before runtime env vars
        # like RAILDOCK_PUBLIC_DOMAIN are resolved.
        TemporaryDomainService.new(project.server).ensure_for(service, engine: engine)

        # Write labels and set network attachment so rebuild works before first deploy
        if project.server.external_proxy?
          host_engine = HostEngine.new(project.server)
          ExternalProxyConfigurator.new(service, engine, host_engine).apply!
          ProjectNetworkManager.new(project, engine).send(:configure_attach_networks, service)
        end
      end

      # Sync storage mounts (only for app services — datastores handle
      # their own internal storage and don't support dokku storage:mount)
      unless service.service_type_database?
        service.storage_mounts.each do |mount|
          ensure_success!(
            engine.storage_mount(app_name, mount.host_path, mount.container_path),
            "mount storage for #{app_name}"
          )
        end
      end
    end
  end

  def create_links(project, template, engine, services)
    services_by_name = services.index_by(&:name)
    host_engine = HostEngine.new(project.server)

    template.links.each do |link|
      from_svc = services_by_name[link[:from]]
      to_svc = services_by_name[link[:to]]
      next unless from_svc && to_svc

      ServiceLink.find_or_create_by!(from_service: from_svc, to_service: to_svc)

      if to_svc.docker_image_database?
        link_result = engine.send("#{to_svc.subtype}_link", to_svc.dokku_app_name, from_svc.dokku_app_name)
        ensure_success!(link_result, "link #{link[:from]} to #{link[:to]}")

        linker = ServiceLinkSetup.new(project, engine, host_engine: host_engine)
        setup_result = linker.setup!(from_svc, to_svc)
        raise "Link setup failed: #{setup_result[:error]}" unless setup_result[:success]
      end
    end
  end

  def connect_networks(project, engine, services)
    network_manager = ProjectNetworkManager.new(project, engine)

    services.each do |service|
      next if service.service_type_database?
      service.reload
      ensure_success!(
        network_manager.configure_attach_networks(service),
        "configure networks for #{service.dokku_app_name}"
      )
    end
  end

  def resolve_runtime_values(project, engine, services)
    app_services = services.select(&:service_type_app?)

    # Resolve runtime variable markers
    app_services.each do |service|
      service.environment_variables.each do |ev|
        next unless ev.value.to_s.include?("[")
        resolved = ManifestParser.resolve_runtime(ev.value, project, service, service.linked_services)
        next if resolved == ev.value

        ensure_success!(
          engine.config_set(service.dokku_app_name, ev.key, resolved),
          "resolve #{ev.key} for #{service.dokku_app_name}"
        )
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

          ensure_success!(
            engine.config_set(service.dokku_app_name, ev.key, actual_url),
            "rewrite #{ev.key} for #{service.dokku_app_name}"
          )
          ev.update!(value: actual_url)
          Rails.logger.info "Rewrote #{ev.key} on #{service.dokku_app_name} to use actual #{db.subtype} credentials from #{url_var}"
        end
      end
    end
  end

  def enqueue_app_deployments(project, services, deployment_ids_by_service)
    app_services = services.select(&:service_type_app?)
    sorted = topo_sort_by_depends_on(app_services)
    deployments_by_service = {}

    sorted.each do |service|
      deployment_id = deployment_ids_by_service&.fetch(service.id.to_s, nil) ||
        deployment_ids_by_service&.fetch(service.id, nil)
      deployment = service.deployments.pending.find_by(id: deployment_id)
      deployment ||= service.deployments.create!(
        status: :pending,
        started_at: Time.current,
        branch: service.branch || "main"
      )
      deployments_by_service[service.id] = deployment
      service.update!(status: :deploying)

      ActivityEvent.create!(
        project: project,
        service_name: service.name,
        action: :deployed,
        message: "Template deploy triggered for #{service.name}"
      )
    end

    DeploymentSequenceJob.perform_later(deployment_sequence_entries(sorted, deployments_by_service)) if deployments_by_service.any?
  end

  def deployment_sequence_entries(services, deployments_by_service)
    ids_by_name = services.index_by(&:name).transform_values(&:id)

    services.map do |service|
      dependency_ids = deployment_dependency_names(service, ids_by_name.keys).filter_map do |name|
        deployments_by_service[ids_by_name[name]]&.id
      end

      {
        service_id: service.id,
        deployment_id: deployments_by_service.fetch(service.id).id,
        depends_on_deployment_ids: dependency_ids
      }
    end
  end

  def scoped_services(project, service_ids)
    return project.services.to_a if service_ids.blank?

    services = project.services.where(id: service_ids).to_a
    missing_ids = Array(service_ids).map(&:to_i) - services.map(&:id)
    raise "Template services not found: #{missing_ids.join(', ')}" if missing_ids.any?

    services
  end

  def ensure_success!(result, action)
    return result if result&.fetch(:success, false)

    output = result&.fetch(:output, nil) || result&.fetch(:error, nil) || "unknown error"
    raise "Failed to #{action}: #{output}"
  end

  def fail_pending_deployments(project, service_ids, deployment_ids_by_service, message)
    deployment_ids = deployment_ids_by_service.to_h.values
    deployments = if deployment_ids.any?
      Deployment.where(id: deployment_ids, status: :pending)
    else
      Deployment.joins(:service).where(
        services: { project_id: project.id, id: Array(service_ids) },
        status: :pending
      )
    end

    service_ids = deployments.pluck(:service_id)
    deployments.update_all(
      status: "failed",
      deploy_log: "Template setup failed: #{message}",
      completed_at: Time.current,
      updated_at: Time.current
    )
    project.services.where(id: service_ids).update_all(status: "error", updated_at: Time.current)
  end

  def topo_sort_by_depends_on(services)
    svc_map = services.map { |s| [ s.name, s ] }.to_h
    in_degree = Hash.new(0)
    dependents = Hash.new { |h, k| h[k] = [] }

    services.each do |svc|
      deps = deployment_dependency_names(svc, svc_map.keys)
      in_degree[svc.name] += 0
      deps.each do |dep|
        dependents[dep] << svc.name
        in_degree[svc.name] += 1
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

  def deployment_dependency_names(service, available_names)
    configured = Array(service.config&.dig("depends_on"))
    linked_apps = service.linked_services.where(service_type: "app").pluck(:name)

    (configured + linked_apps).uniq.select { |name| available_names.include?(name) }
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
