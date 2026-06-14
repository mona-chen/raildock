class DeploymentJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: ->(service_id, deployment_id) { "deploy:#{service_id}" }

  def perform(service_id, deployment_id)
    service = Service.find(service_id)
    project = service.project
    server = project.server
    deployment = service.deployments.find(deployment_id)

    return mark_failed(deployment, service, "No server configured") unless server
    return mark_failed(deployment, service, "No SSH key configured") if server.ssh_key.blank?

    engine = DokkuEngine.new(server)
    host_engine = HostEngine.new(server)

    begin
      # Reuse a single SSH session for the entire deploy. This avoids the
      # connection storm that causes sshd to drop connections during one-click
      # deploys, and keeps long streaming commands alive via keepalives.
      engine.with_session do
        host_engine.with_session do
          perform_deployment(service, project, deployment, engine, host_engine)
        end
      end
    rescue => e
      mark_failed(deployment, service, "Exception: #{e.message}")
    end
  end

  private

  def perform_deployment(service, project, deployment, engine, host_engine)
    server = project.server

    # 0. Wait for linked database services to be ready and reachable.
    #    Dokku datastore:create returns before the container accepts connections,
    #    and docker network aliases need a moment to propagate via embedded DNS.
    databases_ready = wait_for_linked_databases(service, engine, host_engine)
    return mark_failed(deployment, service, "Linked database did not become ready") unless databases_ready

    # 0.5. Connect linked database containers to the project network with
    #      their service name as a DNS alias (e.g. "mysql"). This must happen
    #      BEFORE ps:rebuild starts the app container, so hostname references
    #      like DATABASE_HOST=mysql resolve via Docker DNS on first boot.
    #      For template deploys, connect_networks already handles this; this
    #      covers manifest and git deploys where only DeploymentJob runs.
    ensure_datastore_network_aliases(service, engine, host_engine)

    # 1. Ensure app exists
    unless engine.app_exists?(service.dokku_app_name)
      result = engine.app_create(service.dokku_app_name)
      return mark_failed(deployment, service, "App creation failed", result[:output]) unless result[:success]
    end

    network_manager = ProjectNetworkManager.new(project, engine)
    network_result = network_manager.configure_attach_networks(service)
    return mark_failed(deployment, service, "Network configuration failed", network_result[:output]) unless network_result[:success]

    # 2. Sync environment variables
    service.environment_variables.each do |ev|
      result = engine.config_set(service.dokku_app_name, ev.key, ev.value)
      return mark_failed(deployment, service, "Environment sync failed for #{ev.key}", result[:output]) unless result[:success]
    end

    # 3. Sync domains
    if service.domains.any?
      result = engine.domain_set(service.dokku_app_name, *service.domains.map(&:hostname))
      return mark_failed(deployment, service, "Domain sync failed", result[:output]) unless result[:success]
    end

    # 4. Sync storage mounts
    service.storage_mounts.each do |mount|
      result = engine.storage_mount(service.dokku_app_name, mount.host_path, mount.container_path)
      return mark_failed(deployment, service, "Storage sync failed for #{mount.container_path}", result[:output]) unless result[:success]
    end

    # 5. Apply proxy settings
    if server.external_proxy?
      proxy_result = ExternalProxyConfigurator.new(service, engine, host_engine).apply!
      return mark_failed(deployment, service, "External proxy configuration failed", proxy_result[:output]) unless proxy_result[:success]
    elsif service.config&.dig("proxy", "enabled") == false
      result = engine.proxy_disable(service.dokku_app_name)
      return mark_failed(deployment, service, "Proxy disable failed", result[:output]) unless result[:success]
    else
      if (proxy_type = service.config&.dig("proxy", "proxyType")).present?
        result = engine.proxy_set(service.dokku_app_name, proxy_type)
        return mark_failed(deployment, service, "Proxy selection failed", result[:output]) unless result[:success]
      end

      nginx_result = apply_nginx_settings(engine, service)
      return mark_failed(deployment, service, "Proxy settings failed", nginx_result[:output]) unless nginx_result[:success]

      result = engine.proxy_enable(service.dokku_app_name)
      return mark_failed(deployment, service, "Proxy enable failed", result[:output]) unless result[:success]
    end

    # 6. Apply docker options
    if service.config&.dig("dockerOptions")
      service.config["dockerOptions"].each do |opt|
        next unless opt["phase"] && opt["option"]

        result = engine.docker_option_add(service.dokku_app_name, opt["phase"], opt["option"])
        return mark_failed(deployment, service, "Docker option sync failed", result[:output]) unless result[:success]
      end
    end

    # 7. Apply resource limits
    if service.config&.dig("resourceLimits")
      each_resource_limit(service.config["resourceLimits"]) do |process_type, limits|
        result = engine.resource_limit(
          service.dokku_app_name,
          process_type,
          memory: limits["memory"],
          cpu: limits["cpu"],
          nvidia_gpu: limits["nvidiaGpu"] || limits["nvidia_gpu"]
        )
        return mark_failed(deployment, service, "Resource limit sync failed for #{process_type}", result[:output]) unless result[:success]
      end
    end

    # 8. Set git deploy branch
    branch_result = engine.git_set_deploy_branch(service.dokku_app_name, deployment.branch || service.branch || "main")
    return mark_failed(deployment, service, "Git deploy branch configuration failed", branch_result[:output]) unless branch_result[:success]

    # 9. Deploy (with real-time log streaming)
    deployment.update!(status: :building)
    service.update!(status: :building)
    DeploymentsChannel.broadcast_to(service, {
      deployment_id: deployment.id,
      status: "building",
      message: "Build started",
      started_at: Time.current.iso8601
    })

    deploy_output = ""

    if service.docker_image.present?
      # Docker image deploy: git:from-image builds and deploys synchronously
      # Pre-pull to warm the layer cache and avoid overlayfs extraction races
      # on large images (e.g. ActivePieces with huge node_modules layers)
      pre_pull = host_engine.run("docker pull #{service.docker_image}")
      deploy_output += pre_pull[:output] if pre_pull[:output].present?

      deploy_command = "git:from-image #{service.dokku_app_name} #{service.docker_image}"

      result = engine.run_streaming(deploy_command) do |chunk|
        deploy_output += chunk
        deployment.update!(deploy_log: deploy_output)
        DeploymentsChannel.broadcast_to(service, {
          deployment_id: deployment.id,
          status: "building",
          log_chunk: chunk,
          started_at: deployment.started_at.iso8601
        })
      end

      # Retry once on pull/extraction failures (transient overlayfs races)
      if !result[:success] && deploy_output.match?(/failed to pull image|failed to extract layer|UtimesNanoAt|overlayfs/i)
        Rails.logger.warn "Docker image deploy failed for #{service.dokku_app_name}, retrying after forced pull..."
        deploy_output += "\n\n--- Retrying deploy after forced pull ---\n"

        # Force re-pull
        host_engine.run("docker pull #{service.docker_image}")

        result = engine.run_streaming(deploy_command) do |chunk|
          deploy_output += chunk
          deployment.update!(deploy_log: deploy_output)
          DeploymentsChannel.broadcast_to(service, {
            deployment_id: deployment.id,
            status: "building",
            log_chunk: chunk,
            started_at: deployment.started_at.iso8601
          })
        end
      end
    elsif service.git_repo.present?
      # Git deploy: git:sync only fetches code; ps:rebuild does the actual build
      # Run git:sync first (non-streaming, usually short)
      git_repo = git_repo_for_deploy(service)
      git_ref = deployment.commit_sha.presence || deployment.branch.presence || service.branch.presence || "main"
      sync_result = engine.run("git:sync #{service.dokku_app_name} #{git_repo} #{git_ref}")
      deploy_output += sync_result[:output]
      deployment.update!(deploy_log: deploy_output) if deploy_output.present?

      if !sync_result[:success]
        return mark_failed(deployment, service, "Git sync failed", sync_result[:output])
      end

      # Stream the actual build output from ps:rebuild
      result = engine.run_streaming("ps:rebuild #{service.dokku_app_name}") do |chunk|
        deploy_output += chunk
        deployment.update!(deploy_log: deploy_output)
        DeploymentsChannel.broadcast_to(service, {
          deployment_id: deployment.id,
          status: "building",
          log_chunk: chunk,
          started_at: deployment.started_at.iso8601
        })
      end
    else
      return mark_failed(deployment, service, "No Git repository or Docker image configured for this service")
    end

    # Dokku returns exit code 1 when image hasn't changed; treat as success
    if !result[:success] && deploy_output.include?("No changes detected")
      result = { success: true, output: deploy_output }
    end

    unless result[:success]
      return mark_failed(deployment, service, "Deploy failed", deploy_output)
    end

    deployment.update!(status: :deploying)
    service.update!(status: :deploying)
    DeploymentsChannel.broadcast_to(service, {
      deployment_id: deployment.id,
      status: "deploying",
      message: "Release configuration started",
      started_at: deployment.started_at.iso8601
    })

    # 10. Detect the app's listening port from the running container/image
    begin
      port_detector = PortDetector.new(engine, host_engine: host_engine)
      detected = port_detector.detect(service)
      if detected
        service.update!(detected_port: detected)
        Rails.logger.info "Detected port #{detected} for #{service.dokku_app_name}"
      end
    rescue => e
      Rails.logger.warn "Port detection failed for #{service.dokku_app_name}: #{e.message}"
    end

    if server.external_proxy?
      proxy_result = ExternalProxyConfigurator.new(service.reload, engine, host_engine).apply!
      return mark_failed(deployment, service, "External proxy refresh failed", proxy_result[:output]) unless proxy_result[:success]
    end

    # 11. Sync port mappings for all domains (routes public 80/443 → container target_port)
    target = service.detected_port || 5000
    unless server.external_proxy?
      port_targets = service.domains.any? ? service.domains.map { |domain| domain.target_port || target }.uniq : [ target ]
      port_targets.each do |domain_target|
        %w[http https].zip([ 80, 443 ]).each do |scheme, host_port|
          result = engine.ports_set(service.dokku_app_name, scheme, host_port, domain_target)
          return mark_failed(deployment, service, "Port mapping failed for #{scheme}", result[:output]) unless result[:success]
        end
      end
    end

    # 12. Scale processes (Dokku deploy already started the app)
    service.process_types.each do |pt|
      result = engine.ps_scale(service.dokku_app_name, pt.name, pt.quantity)
      return mark_failed(deployment, service, "Scaling failed for #{pt.name}", result[:output]) unless result[:success]
    end

    # 13. Ensure service is connected to project's private network
    #    and re-add aliases for all linked services (Dokku doesn't persist aliases)
    network_result = network_manager.connect_service(service)
    return mark_failed(deployment, service, "Network connection failed", network_result[:output]) unless network_result[:success]

    alias_result = network_manager.ensure_linked_aliases(service)
    return mark_failed(deployment, service, "Linked network alias failed", alias_result[:output]) unless alias_result[:success]

    hostname_result = network_manager.inject_internal_hostnames(service)
    return mark_failed(deployment, service, "Internal hostname sync failed", hostname_result[:output]) unless hostname_result[:success]

    # 14. For docker-image services, read container env vars and sync password-type
    #     vars to the Service record so linked services can reference them via
    #     ${{ linked.SERVICE.VAR }} at deploy time.
    if service.docker_image.present?
      sync_docker_image_env_vars(service, host_engine)

      # Also update linked apps that have env vars referencing this service's
      # password vars via ${{ linked.SERVICE.VAR }} — they need the resolved
      # password value (not a new random one from a fresh secret() call).
      linked_result = update_linked_app_password_refs(service, project, engine, host_engine)
      return mark_failed(deployment, service, "Linked password propagation failed", linked_result[:output]) unless linked_result[:success]
    end

    # 15. Mark success
    deployment.update!(
      status: :succeeded,
      deploy_log: deploy_output,
      completed_at: Time.current
    )
    update_service_status_after(deployment, service, success: true)

    ActivityEvent.create!(
      project: project,
      service_name: service.name,
      action: :deployed,
      message: "Deployed #{service.dokku_app_name} successfully"
    )

    DeploymentsChannel.broadcast_to(service, {
      deployment_id: deployment.id,
      status: "succeeded",
      message: "Deployment completed successfully",
      completed_at: Time.current.iso8601
    })

    # 16. Check SSL certificate status for all domains
    if server.external_proxy?
      SslStatusChecker.new(host_engine).check_service(service)
    end
  end

  private

  # Wait for linked database containers to report running and for their network
  # aliases to resolve. This prevents apps from booting before MySQL/Postgres/etc.
  # is actually accepting connections.
  def wait_for_linked_databases(service, engine, host_engine)
    linked_dbs = service.linked_services.select(&:service_type_database?)
    return true if linked_dbs.empty?

    linked_dbs.all? do |db|
      wait_for_datastore_ready(engine, host_engine, db)
    end
  end

  def wait_for_datastore_ready(engine, host_engine, db_service, timeout: 120)
    app_name = db_service.dokku_app_name
    subtype = db_service.subtype
    return unless %w[postgres mysql mariadb redis mongo].include?(subtype)

    start = Time.now
    loop do
      elapsed = Time.now - start
      break if elapsed > timeout

      info_method = "#{subtype}_info"
      if engine.respond_to?(info_method)
        info = engine.send(info_method, app_name)
        if info[:success] && info[:status].to_s.downcase == "running"
          Rails.logger.info "Datastore #{app_name} (#{subtype}) is running"
          return true
        end
      end

      # Fallback: check that the container is running
      container = host_engine.dokku_container_name(app_name)
      if container.present? && host_engine.container_running?(container)
        # Additional port readiness check for mysql/postgres/mariadb
        if %w[postgres mysql mariadb].include?(subtype)
          port = { "postgres" => 5432, "mysql" => 3306, "mariadb" => 3306 }[subtype]
          check = host_engine.run("docker exec #{container} sh -c 'timeout 2 bash -c \"</dev/tcp/localhost/#{port}\"'")
          if check[:success]
            Rails.logger.info "Datastore #{app_name} (#{subtype}) port #{port} is open"
            return true
          end
        else
          return true
        end
      end

      sleep 2
    end

    Rails.logger.warn "Timeout waiting for datastore #{app_name} (#{subtype}) to become ready"
    false
  end

  def ensure_datastore_network_aliases(service, engine, host_engine)
    linked_dbs = service.linked_services.select(&:service_type_database?)
    return if linked_dbs.empty?

    ServiceLinkSetup.new(service.project, engine, host_engine: host_engine)
      .ensure_db_network_aliases(linked_dbs)
  end

  def git_repo_for_deploy(service)
    github_source = github_source_for_service(service)
    return service.git_repo unless github_source

    full_name = Service.repo_full_name(service.git_repo)
    return service.git_repo if full_name.blank?

    token = GithubAppService.installation_token(github_source.installation_id)
    escaped_token = ERB::Util.url_encode(token)
    "https://x-access-token:#{escaped_token}@github.com/#{full_name}.git"
  rescue => e
    Rails.logger.warn "GitHub App deploy token resolution failed for service #{service.id}: #{e.message}"
    service.git_repo
  end

  def github_source_for_service(service)
    full_name = Service.repo_full_name(service.git_repo)
    return nil if full_name.blank?

    sources = GitSource.where(provider: "github", connected: true).where.not(installation_id: nil)
    if service.project.organization_id.present?
      sources = sources.where(organization_id: service.project.organization_id)
    else
      sources = sources.where(user_id: service.project.user_id, organization_id: nil)
    end

    sources.find do |source|
      source.repos.any? { |repo| Service.repo_full_name(repo["full_name"] || repo[:full_name] || repo["clone_url"] || repo[:clone_url]) == full_name }
    end
  end

  def apply_nginx_settings(engine, service)
    nginx_config = service.config&.dig("nginx")
    return { success: true } if nginx_config.blank?

    nginx_settings = {
      "clientMaxBodySize" => "client-max-body-size",
      "readTimeout" => "proxy-read-timeout",
      "keepaliveTimeout" => "proxy-send-timeout"
    }

    nginx_settings.each do |source_key, dokku_key|
      value = nginx_config[source_key]
      next if value.blank?

      result = engine.nginx_set(service.dokku_app_name, dokku_key, value)
      return result unless result[:success]
    end

    { success: true }
  end

  def each_resource_limit(resource_limits)
    if resource_limits.is_a?(Hash)
      resource_limits.each { |process_type, limits| yield(process_type, limits.stringify_keys) }
    else
      Array(resource_limits).each do |limits|
        yield(limits["processType"], limits)
      end
    end
  end

  def mark_failed(deployment, service, message, output = nil)
    # Preserve existing streamed logs; only append a brief failure marker
    current_log = deployment.deploy_log || ""
    deploy_log = if current_log.present?
      "#{current_log}\n\n--- #{message} ---"
    elsif output.present?
      output
    else
      message
    end

    deployment.update!(
      status: :failed,
      deploy_log: deploy_log,
      completed_at: Time.current
    )
    update_service_status_after(deployment, service, success: false)

    ActivityEvent.create!(
      project: service.project,
      service_name: service.name,
      action: :warning,
      message: "Deployment failed for #{service.name}: #{message}"
    )

    DeploymentsChannel.broadcast_to(service, {
      deployment_id: deployment.id,
      status: "failed",
      message: message,
      completed_at: Time.current.iso8601
    })
  end

  def update_service_status_after(deployment, service, success:)
    has_queued_deployment = service.deployments
      .where(status: %i[pending building deploying])
      .where.not(id: deployment.id)
      .exists?

    service.update!(status: has_queued_deployment ? :deploying : (success ? :running : :error))
  end

  PASSWORD_VAR_NAMES = %w[
    POSTGRES_PASSWORD POSTGRES_DB_PASSWORD POSTGRES_PASSWORD POSTGRES_USER_PASSWORD
    MYSQL_ROOT_PASSWORD MYSQL_PASSWORD MARIADB_ROOT_PASSWORD MARIADB_PASSWORD
    REDIS_PASSWORD MONGO_PASSWORD MONGODB_PASSWORD
    DB_PASSWORD DATABASE_PASSWORD DB_PASS
    PASSWORD SECRET SECRET_KEY SECRET_KEY_BASE
    ENCRYPTION_KEY ENCRYPTION_KEY_BASE
    ADMIN_TOKEN ADMIN_PASSWORD APP_SECRET SESSION_SECRET
    AUTH_SECRET AUTH_TOKEN API_SECRET API_KEY
  ].freeze

  def sync_docker_image_env_vars(service, host_engine)
    container_name = host_engine.dokku_container_name(service.dokku_app_name)
    return unless container_name.present?

    result = host_engine.docker_inspect(container_name, format: "{{range .Config.Env}}{{.}}\\n{{end}}")
    return unless result[:success] && result[:output].present?

    result[:output].each_line do |line|
      line = line.strip
      next unless line.include?("=")
      key, _, value = line.partition("=")
      key = key.strip
      value = value.strip
      next unless PASSWORD_VAR_NAMES.any? { |p| key.upcase.include?(p) }
      next if value.blank? || value.start_with?("$")

      existing = service.environment_variables.find_by(key: key)
      if existing
        existing.update!(value: value) if existing.value != value
      else
        service.environment_variables.create!(key: key, value: value, source: "container-inspect")
      end
    end
  rescue => e
    Rails.logger.warn "Failed to sync docker image env vars for #{service.dokku_app_name}: #{e.message}"
  end

  # After syncing password vars from a docker-image container, find any linked
  # apps that have [LINKED:SERVICE:VAR] markers in their env vars pointing to
  # those password vars, and update the linked app's env var with the resolved
  # (not re-randomized) password value so the container gets the right credential.
  def update_linked_app_password_refs(service, project, engine, host_engine)
    service.reload

    # Find all services that link TO this service (i.e., services that have
    # this service as a dependency in their [[links]] section).
    # For example, if autobase-api links to autobase-db, then when we deploy
    # autobase-db, we need to update autobase-api's [LINKED:autobase-db:VAR] refs.
    linking_services = Service.where.not(id: service.id).select do |s|
      s.linked_services.any? { |linked| linked.id == service.id }
    end

    linking_services.each do |linked_app|
      had_updates = false
      linked_app.environment_variables.each do |ev|
        next unless ev.value.to_s.include?("[LINKED:")

        ev.value.to_s.scan(/\[LINKED:([A-Za-z][A-Za-z0-9_-]*):([A-Za-z_][A-Za-z0-9_]*)\]/) do |svc_name, var_name|
          next unless svc_name == service.name

          password_value = service.environment_variables.find_by(key: var_name)&.value
          next if password_value.blank?

          resolved = ManifestParser.resolve_runtime(ev.value, project, linked_app, linked_app.linked_services)
          next if resolved == ev.value || resolved.include?("[")

          set_result = engine.config_set(linked_app.dokku_app_name, ev.key, resolved)
          return set_result unless set_result[:success]
          ev.update!(value: resolved)
          had_updates = true
          Rails.logger.info "Updated #{ev.key} on #{linked_app.dokku_app_name} via linked ref to #{service.name}.#{var_name}"
        end
      end

      # Restart the linked app's container so it picks up the new password value
      if had_updates
        container = host_engine.dokku_container_name(linked_app.dokku_app_name)
        if container.present? && host_engine.container_running?(container)
          restart_result = host_engine.run("docker restart #{container}")
          return restart_result unless restart_result[:success]
          Rails.logger.info "Restarted #{container} to pick up resolved linked password"
        end
      end
    end
    { success: true }
  rescue => e
    Rails.logger.warn "Failed to update linked app password refs for #{service.dokku_app_name}: #{e.message}"
    { success: false, output: e.message }
  end
end
