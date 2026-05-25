class DeploymentJob < ApplicationJob
  queue_as :default

  def perform(service_id, deployment_id)
    service = Service.find(service_id)
    project = service.project
    server = project.server
    deployment = service.deployments.find(deployment_id)

    return mark_failed(deployment, service, "No server configured") unless server
    return mark_failed(deployment, service, "No SSH key configured") if server.ssh_key.blank?

    engine = DokkuEngine.new(server)

    begin
      # 1. Ensure app exists
      unless engine.app_exists?(service.dokku_app_name)
        result = engine.app_create(service.dokku_app_name)
        return mark_failed(deployment, service, "App creation failed", result[:output]) unless result[:success]
      end

      # 2. Sync environment variables
      service.environment_variables.each do |ev|
        engine.config_set(service.dokku_app_name, ev.key, ev.value)
      end

      # 3. Sync domains
      service.domains.each do |domain|
        engine.domain_add(service.dokku_app_name, domain.hostname)
      end

      # 4. Sync storage mounts
      service.storage_mounts.each do |mount|
        engine.storage_mount(service.dokku_app_name, mount.host_path, mount.container_path)
      end

      # 5. Apply proxy settings
      if service.config&.dig("proxy", "enabled") == false
        engine.proxy_disable(service.dokku_app_name)
      else
        engine.proxy_enable(service.dokku_app_name)
      end

      # 6. Apply docker options
      if service.config&.dig("dockerOptions")
        service.config["dockerOptions"].each do |opt|
          engine.docker_option_add(service.dokku_app_name, opt["phase"], opt["option"]) if opt["phase"] && opt["option"]
        end
      end

      # 7. Apply resource limits
      if service.config&.dig("resourceLimits")
        service.config["resourceLimits"].each do |res|
          engine.resource_limit(
            service.dokku_app_name,
            res["processType"],
            memory: res["memory"],
            cpu: res["cpu"],
            nvidia_gpu: res["nvidiaGpu"]
          )
        end
      end

      # 8. Set git deploy branch
      engine.git_set_deploy_branch(service.dokku_app_name, service.branch || "main")

      # 9. Deploy (with real-time log streaming)
      deployment.update!(status: :deploying)
      DeploymentsChannel.broadcast_to(service, {
        deployment_id: deployment.id,
        status: "deploying",
        message: "Deployment started",
        started_at: Time.current.iso8601
      })

      deploy_output = ""

      if service.docker_image.present?
        # Docker image deploy: git:from-image builds and deploys synchronously
        # Pre-pull to warm the layer cache and avoid overlayfs extraction races
        # on large images (e.g. ActivePieces with huge node_modules layers)
        pre_pull = engine.run("docker pull #{service.docker_image}")
        deploy_output += pre_pull[:output] if pre_pull[:output].present?

        deploy_command = "git:from-image #{service.dokku_app_name} #{service.docker_image}"

        result = engine.run_streaming(deploy_command) do |chunk|
          deploy_output += chunk
          deployment.update!(deploy_log: deploy_output)
          DeploymentsChannel.broadcast_to(service, {
            deployment_id: deployment.id,
            status: "deploying",
            log_chunk: chunk,
            started_at: deployment.started_at.iso8601
          })
        end

        # Retry once on pull/extraction failures (transient overlayfs races)
        if !result[:success] && deploy_output.match?(/failed to pull image|failed to extract layer|UtimesNanoAt|overlayfs/i)
          Rails.logger.warn "Docker image deploy failed for #{service.dokku_app_name}, retrying after forced pull..."
          deploy_output += "\n\n--- Retrying deploy after forced pull ---\n"

          # Force re-pull
          engine.run("docker pull #{service.docker_image}")

          result = engine.run_streaming(deploy_command) do |chunk|
            deploy_output += chunk
            deployment.update!(deploy_log: deploy_output)
            DeploymentsChannel.broadcast_to(service, {
              deployment_id: deployment.id,
              status: "deploying",
              log_chunk: chunk,
              started_at: deployment.started_at.iso8601
            })
          end
        end
      elsif service.git_repo.present?
        # Git deploy: git:sync only fetches code; ps:rebuild does the actual build
        # Run git:sync first (non-streaming, usually short)
        sync_result = engine.run("git:sync #{service.dokku_app_name} #{service.git_repo} #{deployment.branch || service.branch || 'main'}")
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
            status: "deploying",
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

      # 10. Detect the app's listening port from the running container/image
      begin
        port_detector = PortDetector.new(engine)
        detected = port_detector.detect(service)
        if detected
          service.update!(detected_port: detected)
          Rails.logger.info "Detected port #{detected} for #{service.dokku_app_name}"
        end
      rescue => e
        Rails.logger.warn "Port detection failed for #{service.dokku_app_name}: #{e.message}"
      end

      # 11. Sync port mappings for all domains (routes public 80/443 → container target_port)
      begin
        target = service.detected_port || 5000
        if service.domains.any?
          service.domains.each do |domain|
            domain_target = domain.target_port || target
            engine.ports_set(service.dokku_app_name, "http", 80, domain_target)
            engine.ports_set(service.dokku_app_name, "https", 443, domain_target)
          end
        else
          # No domains yet — still set a default port mapping so the app is accessible
          engine.ports_set(service.dokku_app_name, "http", 80, target)
          engine.ports_set(service.dokku_app_name, "https", 443, target)
        end
      rescue => e
        Rails.logger.warn "Port mapping sync failed for #{service.dokku_app_name}: #{e.message}"
      end

      # 12. Scale processes (Dokku deploy already started the app)
      service.process_types.each do |pt|
        engine.ps_scale(service.dokku_app_name, pt.name, pt.quantity)
      end

      # 13. Ensure service is connected to project's private network
      #    and re-add aliases for all linked services (Dokku doesn't persist aliases)
      begin
        network_manager = ProjectNetworkManager.new(project, engine)
        network_manager.connect_service(service)
        network_manager.ensure_linked_aliases(service)
        network_manager.inject_internal_hostnames(service)
      rescue => e
        Rails.logger.warn "Network connect failed for #{service.dokku_app_name}: #{e.message}"
      end

      # 14. For docker-image services, read container env vars and sync password-type
      #     vars to the Service record so linked services can reference them via
      #     ${{ linked.SERVICE.VAR }} at deploy time.
      if service.docker_image.present?
        sync_docker_image_env_vars(service, project)

        # Also update linked apps that have env vars referencing this service's
        # password vars via ${{ linked.SERVICE.VAR }} — they need the resolved
        # password value (not a new random one from a fresh secret() call).
        update_linked_app_password_refs(service, project)
      end

      # 15. Mark success
      deployment.update!(
        status: :succeeded,
        deploy_log: deploy_output,
        completed_at: Time.current
      )
      service.update!(status: :running)

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
    rescue => e
      mark_failed(deployment, service, "Exception: #{e.message}")
    end
  end

  private

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
    service.update!(status: :error)

    ActivityEvent.create!(
      project: service.project,
      service_name: service.name,
      action: :created,
      message: "Deployment failed for #{service.name}: #{message}"
    )

    DeploymentsChannel.broadcast_to(service, {
      deployment_id: deployment.id,
      status: "failed",
      message: message,
      completed_at: Time.current.iso8601
    })
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

  def sync_docker_image_env_vars(service, project)
    container_name = HostEngine.new(project.server).dokku_container_name(service.dokku_app_name)
    return unless container_name.present?

    result = HostEngine.new(project.server).docker_inspect(container_name, format: "{{range .Config.Env}}{{.}}\\n{{end}}")
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
  def update_linked_app_password_refs(service, project)
    service.reload
    return if service.linked_services.empty?

    service.linked_services.each do |linked_app|
      linked_app.environment_variables.each do |ev|
        next unless ev.value.to_s.include?("[LINKED:")
        linked_svc_name = service.name

        ev.value.to_s.scan(/\[LINKED:([A-Za-z][A-Za-z0-9_-]*):([A-Za-z_][A-Za-z0-9_]*)\]/) do |svc_name, var_name|
          next unless svc_name == linked_svc_name

          password_value = service.environment_variables.find_by(key: var_name)&.value
          next if password_value.blank?

          resolved = ManifestParser.resolve_runtime(ev.value, project, linked_app, linked_app.linked_services)
          next if resolved == ev.value || resolved.include?("[")

          engine = DokkuEngine.new(project.server)
          engine.config_set(linked_app.dokku_app_name, ev.key, resolved)
          ev.update!(value: resolved)
          Rails.logger.info "Updated #{ev.key} on #{linked_app.dokku_app_name} via linked ref to #{linked_svc_name}.#{var_name}"
        end
      end
    end
  rescue => e
    Rails.logger.warn "Failed to update linked app password refs for #{service.dokku_app_name}: #{e.message}"
  end
end
