module Api
  class ServicesController < BaseController
    include Authorizable
    include DokkuEnvBatchable

    # Standard error response format
    ERROR_RESPONSE = ->(message = nil, details = nil) {
      response = { error: message }
      response[:details] = details if details
      response
    }.call

    before_action :set_and_authorize_service!, only: [
      :show, :update, :destroy, :deploy, :rollback, :container_status,
      :start, :stop, :restart, :rebuild, :scale, :logs, :link, :unlink,
      :metrics, :metrics_history, :backup, :restore, :restore_backup, :download_backup, :destroy_backup,
      :database_info, :backups, :snapshots, :backup_schedules,
      :create_backup_schedule, :destroy_backup_schedule, :run, :enter, :linked_by,
      :generate_domain
    ]

    def index
      project = scoped_projects.find(params[:project_id])
      authorize_project!(project)
      services = project.services
      render json: services
    end

    def show
      render json: @service
    end

    def create
      project = scoped_projects.find(params[:project_id])
      authorize_project!(project, action: :create)

      server = project.server

      # Inherit server's default proxy type
      proxy_config = { enabled: true, proxyType: server&.default_proxy || "traefik", portMappings: [] }

      attrs = service_params.merge(
        project_id: params[:project_id],
        config: (service_params[:config] || {}).merge(proxy: proxy_config)
      )
      # Frontend sends 'category', backend expects 'service_type'
      attrs[:service_type] ||= params[:category] || params[:service_type]
      attrs[:name] ||= params[:name]
      attrs[:subtype] ||= params[:subtype]
      attrs[:status] ||= "stopped"

      # Auto-assign default Docker image for registered one-click service subtypes
      if attrs[:docker_image].blank? && attrs[:git_repo].blank?
        attrs[:docker_image] ||= PluginRegistry.find_subtype(attrs[:subtype])&.default_image || Service::DEFAULT_DOCKER_IMAGES[attrs[:subtype]]
      end

      # Auto-assign default builder for app services
      if attrs[:service_type] == "app" && attrs[:builder].blank?
        source_type = attrs[:git_repo].present? ? "git" : (attrs[:docker_image].present? ? "docker" : "git")
        attrs[:builder] = PluginRegistry.default_builder_for(attrs[:subtype], source_type)&.slug
      end

      service = Service.create!(attrs)

      # Create Dokku resource if server is connected and has SSH key
      with_dokku_engine(service) do |engine|
        if service.subtype_record&.has_capability?(:create)
          result = engine.datastore_create(service)
          service.update!(status: :running) if result && result[:success]
        else
          engine.app_create(service.dokku_app_name)
          engine.proxy_set(service.dokku_app_name, proxy_config[:proxyType] || "traefik") unless server.external_proxy?
          TemporaryDomainService.new(server).ensure_for(service, engine: engine)

          # Configure external proxy labels and network attachment immediately
          # so rebuild works before first deploy.
          if server.external_proxy?
            host_engine = HostEngine.new(server)
            ExternalProxyConfigurator.new(service, engine, host_engine).apply!
            ProjectNetworkManager.new(service.project, engine).send(:configure_attach_networks, service)
          end
        end
      end

      ActivityEvent.create!(
        project: service.project,
        service_name: service.name,
        action: :created,
        message: "Created #{service.name} (#{service.subtype})"
      )
      render json: service, status: :created
    end

    def update
      authorize_service!(@service, action: :update)

      # For hybrid/manifest-managed services, store UI overrides separately
      if @service.managed_by_hybrid? || @service.managed_by_manifest?
        merge_config_overrides!
      end

      @service.update!(service_params)

      with_dokku_engine(@service) do |engine|
        ServiceSettingsSync.new(@service, engine).sync_config_changes!
      end

      render json: @service
    end

    def destroy
      authorize_service!(@service, action: :delete)

      # Destroy Dokku resource if server connected
      with_dokku_engine(@service) do |engine|
        if @service.subtype_record&.has_capability?(:destroy)
          engine.datastore_destroy(@service)
        else
          engine.app_destroy(@service.dokku_app_name)
        end
      end

      @service.destroy!
      ActivityEvent.create!(
        project: @service.project,
        service_name: @service.name,
        action: :destroyed,
        message: "Destroyed #{@service.name}"
      )
      head :no_content
    end

    def deploy
      authorize_service!(@service, action: :deploy)

      if @service.service_type == "database"
        render json: ERROR_RESPONSE.merge(error: "Database services cannot be deployed. They are managed directly by Dokku."), status: :unprocessable_entity
        return
      end

      deployment = @service.deployments.create!(
        status: :pending,
        started_at: Time.current,
        branch: params[:branch] || @service.branch || "main",
        commit_sha: params[:commit_sha],
        commit_message: params[:commit_message],
        triggered_by: "manual"
      )

      DeploymentJob.perform_later(@service.id, deployment.id)

      @service.update!(status: :deploying)
      ActivityEvent.create!(
        project: @service.project,
        service_name: @service.name,
        action: :deployed,
        message: "Deployment triggered for #{@service.name}"
      )

      render json: deployment
    end

    def rollback
      authorize_service!(@service, action: :deploy)

      target = @service.deployments.find(params[:deployment_id])
      if @service.git_repo.present? && target.commit_sha.blank?
        return render json: {
          error: "This deployment has no commit SHA and cannot be rolled back precisely"
        }, status: :unprocessable_entity
      end

      # Create a new deployment with the previous commit
      deployment = @service.deployments.create!(
        status: :pending,
        started_at: Time.current,
        branch: target.branch || @service.branch || "main",
        commit_sha: target.commit_sha,
        commit_message: "Rollback: #{target.commit_message.presence || target.commit_sha.to_s.first(7)}",
        triggered_by: "rollback"
      )

      DeploymentJob.perform_later(@service.id, deployment.id)

      @service.update!(status: :deploying)
      ActivityEvent.create!(
        project: @service.project,
        service_name: @service.name,
        action: :deployed,
        message: "Rollback to #{target.commit_sha || target.branch} for #{@service.name}"
      )

      render json: deployment
    end

    def container_status
      with_dokku_engine(@service) do |engine|
        if engine
          if @service.service_type_database?
            info_method = "#{@service.subtype}_info"
            if engine.respond_to?(info_method)
              info = engine.send(info_method, @service.dokku_app_name)
              if info[:success]
                db_status = info[:status].to_s.downcase == "running" ? "running" : "error"
                return render json: { status: db_status, output: info }
              end
            end
          else
            result = engine.container_status(@service.dokku_app_name)
            if result[:success]
              running = result[:output].to_s.strip.downcase == "true"
              status = running ? "running" : "error"
              return render json: { status: status, output: result[:output] }
            end
          end
        end
      end

      render json: { status: @service.status }
    end

    def start
      authorize_service!(@service, action: :update)

      with_dokku_engine(@service) do |engine|
        result = engine.ps_start(@service.dokku_app_name)
        if result[:success]
          @service.update!(status: "running")
          ActivityEvent.create!(
            project: @service.project,
            service_name: @service.name,
            action: :started,
            message: "Started #{@service.name}"
          )
          return render json: { success: true, status: "running" }
        else
          return render json: { success: false, error: result[:output] }, status: :unprocessable_entity
        end
      end

      @service.update!(status: "running")
      render json: { success: true, status: "running" }
    end

    def stop
      authorize_service!(@service, action: :update)

      with_dokku_engine(@service) do |engine|
        result = engine.ps_stop(@service.dokku_app_name)
        if result[:success]
          @service.update!(status: "stopped")
          ActivityEvent.create!(
            project: @service.project,
            service_name: @service.name,
            action: :stopped,
            message: "Stopped #{@service.name}"
          )
          return render json: { success: true, status: "stopped" }
        else
          return render json: { success: false, error: result[:output] }, status: :unprocessable_entity
        end
      end

      @service.update!(status: "stopped")
      render json: { success: true, status: "stopped" }
    end

    def restart
      authorize_service!(@service, action: :update)

      if @service.project&.server&.ssh_key.blank?
        return render json: { error: "No server configured" }, status: :unprocessable_entity
      end

      idempotency_key = "restart:#{@service.id}:#{params[:nonce] || Time.current.to_f}"
      RestartJob.perform_later(@service.id, idempotency_key: idempotency_key)

      # Look up the (or create the) deployment so we can return its id for the UI
      # to subscribe to log streaming.
      deployment = @service.deployments.find_by(idempotency_key: idempotency_key) ||
                  @service.deployments.where(kind: "restart").order(created_at: :desc).first

      render json: {
        success: true,
        queued: true,
        deployment_id: deployment&.id
      }
    end

    def rebuild
      authorize_service!(@service, action: :update)

      with_dokku_engine(@service) do |engine|
        result = engine.ps_rebuild(@service.dokku_app_name)
        if result[:success]
          @service.update!(status: "running")
          ActivityEvent.create!(
            project: @service.project,
            service_name: @service.name,
            action: :rebuilt,
            message: "Rebuilt #{@service.name}"
          )
          return render json: { success: true, status: "running" }
        else
          return render json: { success: false, error: result[:output] }, status: :unprocessable_entity
        end
      end

      @service.update!(status: "running")
      render json: { success: true, status: "running" }
    end

    def scale
      authorize_service!(@service, action: :update)

      process_name = params[:process_name] || params[:processName]
      quantity = params[:quantity]
      process = @service.process_types.find_by!(name: process_name)
      process.update!(quantity: quantity)

      # Sync to Dokku if server connected
      with_dokku_engine(@service) do |engine|
        engine.ps_scale(@service.dokku_app_name, process_name, quantity)
      end

      ActivityEvent.create!(
        project: @service.project,
        service_name: @service.name,
        action: :scaled,
        message: "Scaled #{process_name} to #{quantity} instances"
      )

      render json: @service
    end

    def logs
      with_dokku_engine(@service) do |engine|
        if @service.subtype_record&.has_capability?(:logs)
          result = engine.datastore_logs(@service)
        else
          result = engine.logs(@service.dokku_app_name, lines: 100)
        end

        if result[:success]
          lines = result[:output].split("\n").map do |line|
            { timestamp: Time.current.iso8601, processType: @service.subtype, message: line }
          end
          return render json: lines
        end
      end

      # Fallback to stored logs
      render json: @service.logs
    end

    def link
      target = Service.find(params[:target_id])
      authorize_service!(target, action: :read)

      # Create the link record — idempotent, silently succeed if already linked
      link = ServiceLink.find_or_initialize_by(from_service: @service, to_service: target)
      is_new_link = link.new_record?
      link.save!

      # Only sync to Dokku if this is a newly-created link
      if is_new_link
        with_dokku_engine(@service) do |engine|
          if target.subtype_record&.has_capability?(:link)
            link_result = engine.datastore_link(target, @service.dokku_app_name)

            unless link_result&.dig(:success)
              Rails.logger.error "Dokku link failed: #{link_result&.dig(:output)}"
              return render json: { error: "Dokku link failed: #{link_result&.dig(:output)}" }, status: :unprocessable_entity
            end

            # Fetch and sync Dokku-injected env vars (DATABASE_URL, REDIS_URL, etc.)
            sync_dokku_env_vars(engine, @service)

            # Disable SSL cert validation for internal connections when the subtype requests it
            if target.subtype_record&.sslmode.present?
              engine.config_set(@service.dokku_app_name, "PGSSLMODE", target.subtype_record.sslmode)
              @service.environment_variables.find_or_initialize_by(key: "PGSSLMODE").update!(value: target.subtype_record.sslmode)
            end
          end

          # Connect both services to the project's private network
          # so they can resolve each other by internal hostname
          network_manager = ProjectNetworkManager.new(@service.project, engine)
          network_manager.connect_service(@service)
          network_manager.connect_service(target)
          network_manager.ensure_linked_aliases(@service)
          network_manager.inject_internal_hostnames(@service)

          # Update app env vars to use the linked service's alias hostname
          # and sync credentials from the linked service's env vars
          sync_linked_service_env_vars(engine, @service, target)
        end

        ActivityEvent.create!(
          project: @service.project,
          service_name: @service.name,
          action: :linked,
          message: "Linked #{@service.name} to #{target.name}"
        )
      end

      render json: { success: true, linked_service_ids: @service.reload.linked_service_ids }
    end

    def unlink
      target = Service.find(params[:target_id])
      authorize_service!(target, action: :read)

      # Remove the link record — look in both directions since the canvas may
      # have created the link from either side.
      link = ServiceLink.find_by(from_service: @service, to_service: target) ||
             ServiceLink.find_by(from_service: target, to_service: @service)

      unless link
        render json: { error: "Link not found" }, status: :not_found
        return
      end

      link.destroy!

      # Determine which side is the app and which is the database for Dokku
      app_service  = @service.service_type_app?  ? @service : target
      db_service   = target.service_type_database? ? target : @service

      # Sync to Dokku if server connected
      with_dokku_engine(app_service) do |engine|
        if db_service.subtype_record&.has_capability?(:unlink)
          engine.datastore_unlink(db_service, app_service.dokku_app_name)

          # Remove env vars that were injected by this link
          remove_linked_env_vars(app_service, db_service)
        end
      end

      ActivityEvent.create!(
        project: @service.project,
        service_name: @service.name,
        action: :unlinked,
        message: "Unlinked #{@service.name} from #{target.name}"
      )

      render json: { success: true, linked_service_ids: @service.reload.linked_service_ids }
    end

    def metrics
      server = @service.project&.server
      if server&.ssh_key.present?
        host_engine = HostEngine.new(server)
        container = host_engine.dokku_container_name(@service.dokku_app_name)
        if container.present?
          stats = host_engine.docker_stats(container)
          if stats
            return render json: {
              cpu: stats[:cpu],
              cpuCores: stats[:cpu_cores],
              memory: stats[:memory],
              memoryUsed: stats[:memory_used],
              memoryLimit: stats[:memory_limit],
              networkIn: 0,
              networkOut: 0
            }
          end
        end
      end

      render json: { cpu: nil, memory: nil, networkIn: 0, networkOut: 0 }
    end

    # Historical time series from service_metrics. Optional ?hours= window
    # (default 24h, max 168h). Returns chronologically ordered samples.
    def metrics_history
      hours = [ params[:hours].to_i.clamp(1, 168), 24 ].max
      since = hours.hours.ago

      samples = @service.service_metrics
        .where(sampled_at: since..)
        .order(:sampled_at)
        .pluck(:sampled_at, :cpu, :cpu_cores, :memory, :memory_used, :memory_limit)

      render json: {
        service: @service.name,
        window_hours: hours,
        samples: samples.map do |t, cpu, cores, mem, used, limit|
          {
            at: t.iso8601,
            cpu: cpu,
            cpu_cores: cores,
            memory: mem,
            memory_used: used,
            memory_limit: limit
          }
        end
      }
    end

    def database_info
      with_dokku_engine(@service) do |engine|
        if @service.subtype_record&.has_capability?(:info)
          result = engine.datastore_info(@service)
        else
          result = { success: false, error: "Unsupported database type" }
        end
        return render json: result
      end

      render json: { success: false, error: "No server configured" }
    end

    def backup
      authorize_service!(@service, action: :update)
      return render json: { error: "Backups are only available for databases" }, status: :unprocessable_entity unless @service.service_type_database?
      return render json: { error: "No server configured" }, status: :unprocessable_entity unless @service.project.server&.ssh_key.present?

      destination_ids = Array(params[:backup_destination_ids]).compact_blank.map(&:to_s)
      if destination_ids.any?
        server = @service.project.server
        visible_ids = server.backup_destinations.ids + server.organization&.backup_destinations&.ids.to_a
        invalid = destination_ids - visible_ids.map(&:to_s)
        return render json: { error: "Invalid backup destination(s): #{invalid.join(", ")}" }, status: :unprocessable_entity if invalid.any?
      end

      metadata = { "trigger" => "manual", "destination_ids" => destination_ids }
      backup_record = @service.backups.create!(status: "pending", metadata: metadata)
      BackupJob.perform_later(backup_record.id)
      render json: { success: true, backup: backup_record }, status: :accepted
    end

    def restore
      authorize_service!(@service, action: :update)
      return render json: { error: "Restores are only available for databases" }, status: :unprocessable_entity unless @service.service_type_database?

      max_bytes = ENV.fetch("RAILDOCK_MAX_RESTORE_BYTES", 10.gigabytes).to_i
      if request.content_length.to_i > max_bytes
        return render json: { error: "Restore artifact exceeds the configured size limit" }, status: :content_too_large
      end

      with_dokku_engine(@service) do |engine|
        result = Tempfile.create([ "raildock-restore", ".dump" ], binmode: true) do |file|
          IO.copy_stream(request.body, file, max_bytes + 1)
          if file.size > max_bytes
            { success: false, output: "Restore artifact exceeds the configured size limit" }
          else
            file.flush
            engine.datastore_import_from(@service, file.path)
          end
        end

        if result[:success]
          ActivityEvent.create!(
            project: @service.project,
            service_name: @service.name,
            action: :created,
            message: "Restored #{@service.name} from backup"
          )
          return render json: { success: true, message: "Restore completed" }
        else
          return render json: { success: false, error: result[:output] }, status: :unprocessable_entity
        end
      end

      render json: { success: false, error: "No server configured" }, status: :unprocessable_entity
    end

    def backups
      render json: @service.backups.where.not(backup_kind: "wal").recent.limit(100)
    end

    def snapshots
      render json: @service.backups.where(backup_kind: "volume").recent.limit(100)
    end

    def download_backup
      backup = @service.backups.find(params[:backup_id])
      return render json: { error: "Backup artifact is unavailable" }, status: :not_found unless backup.available?

      response.headers["Content-Type"] = "application/octet-stream"
      response.headers["Content-Disposition"] = %(attachment; filename="#{@service.name}-#{backup.id}.backup")
      self.response_body = Enumerator.new do |stream|
        BackupArtifactStore.new.materialize(backup) do |path|
          File.open(path, "rb") do |file|
            while (chunk = file.read(1.megabyte))
              stream << chunk
            end
          end
        end
      end
    end

    def restore_backup
      authorize_service!(@service, action: :update)
      backup = @service.backups.find(params[:backup_id])
      return render json: { error: "Backup artifact is unavailable" }, status: :not_found unless backup.available?

      result = case backup.backup_kind
      when "database"
        outcome = nil
        BackupArtifactStore.new.materialize(backup) do |path|
          outcome = DokkuEngine.new(@service.project.server).datastore_import_from(@service, path)
        end
        outcome
      when "volume"
        host_path = backup.metadata&.fetch("host_path", nil)
        return render json: { error: "Volume snapshot is missing its target mount" }, status: :unprocessable_entity if host_path.blank?

        outcome = nil
        BackupArtifactStore.new.materialize(backup) do |path|
          outcome = HostEngine.new(@service.project.server).volume_import_from(host_path, path)
        end
        outcome
      else
        return render json: { error: "This recovery artifact cannot be restored directly" }, status: :unprocessable_entity
      end
      return render json: { error: result[:output] }, status: :unprocessable_entity unless result[:success]

      ActivityEvent.create!(project: @service.project, service_name: @service.name, action: :created, message: "Restored #{@service.name} from verified backup", metadata: { backup_id: backup.id })
      render json: { success: true }
    end

    def destroy_backup
      authorize_service!(@service, action: :delete)
      @service.backups.find(params[:backup_id]).remove_file!
      head :no_content
    end

    def backup_schedules
      render json: @service.backup_schedules
    end

    def create_backup_schedule
      authorize_service!(@service, action: :update)

      schedule = @service.backup_schedules.create!(backup_schedule_params)
      schedule.update_next_run!
      render json: schedule, status: :created
    end

    def destroy_backup_schedule
      schedule = @service.backup_schedules.find(params[:schedule_id])
      authorize_service!(@service, action: :delete)
      schedule.destroy!
      head :no_content
    end

    def run
      authorize_service!(@service, action: :update)

      command = params[:command]
      unless command.present?
        return render json: { error: "Command is required" }, status: :unprocessable_entity
      end

      with_dokku_engine(@service) do |engine|
        result = engine.run_one_off(@service.dokku_app_name, command)
        return render json: { success: result[:success], output: result[:output] }
      end

      render json: { error: "No server configured" }, status: :unprocessable_entity
    end

    def enter
      authorize_service!(@service, action: :update)

      process_type = params[:process_type] || params[:processType] || "web"

      with_dokku_engine(@service) do |engine|
        result = engine.enter_container(@service.dokku_app_name, process_type: process_type)
        return render json: { success: result[:success], output: result[:output] }
      end

      render json: { error: "No server configured" }, status: :unprocessable_entity
    end

    def app_lock
      with_dokku_engine(@service) do |engine|
        result = engine.app_lock(@service.dokku_app_name)
        return render json: { success: result[:success], output: result[:output] }
      end
    end

    def repair_env
      authorize_service!(@service, action: :update)

      if @service.project&.server&.ssh_key.blank?
        return render json: { error: "No server configured" }, status: :unprocessable_entity
      end

      engine = DokkuEngine.new(@service.project.server)
      env_hash = build_full_env_hash(@service, engine)

      result = engine.config_replace_all(@service.dokku_app_name, env_hash)
      unless result[:success]
        return render json: { error: result[:error] || "Sync failed: #{result[:output].to_s.truncate(300)}" },
                      status: :unprocessable_entity
      end

      render json: { success: true, synced: env_hash.size }
    end

    def app_unlock
      with_dokku_engine(@service) do |engine|
        result = engine.app_unlock(@service.dokku_app_name)
        return render json: { success: result[:success], output: result[:output] }
      end
      render json: { error: "No server configured" }, status: :unprocessable_entity
    end

    def app_locked
      with_dokku_engine(@service) do |engine|
        result = engine.app_locked?(@service.dokku_app_name)
        return render json: { locked: result }
      end
      render json: { error: "No server configured" }, status: :unprocessable_entity
    end

    def config_show
      project = scoped_projects.find_by(id: params[:project_id])
      authorize_project!(project)
      service = Service.find(params[:service_id])
      authorize_service!(service)

      with_dokku_engine(service) do |engine|
        result = engine.config_show(service.dokku_app_name)
        return render json: { success: result[:success], output: result[:output] }
      end

      render json: { error: "No server configured" }, status: :unprocessable_entity
    end

    def traefik_config
      project = scoped_projects.find_by(id: params[:project_id])
      authorize_project!(project)
      service = Service.find(params[:service_id])
      authorize_service!(service)

      with_dokku_engine(service) do |engine|
        result = engine.traefik_report(service.dokku_app_name)
        return render json: { success: result[:success], output: result[:output] }
      end

      render json: { error: "No server configured" }, status: :unprocessable_entity
    end

    def storage_list
      project = scoped_projects.find_by(id: params[:project_id])
      authorize_project!(project)
      service = Service.find(params[:service_id])
      authorize_service!(service)

      with_dokku_engine(service) do |engine|
        result = engine.storage_list(service.dokku_app_name)
        return render json: { success: result[:success], output: result[:output] }
      end

      render json: { error: "No server configured" }, status: :unprocessable_entity
    end

    def linked_by
      render json: @service.incoming_links.includes(:from_service).map(&:from_service)
    end

    def generate_domain
      authorize_service!(@service, action: :update)
      server = @service.project&.server

      return render json: { error: "No server configured" }, status: :unprocessable_entity unless server

      hostname = server.temporary_hostname(@service.dokku_app_name)
      return render json: { error: "Could not generate hostname" }, status: :unprocessable_entity unless hostname

      # Check for collision
      if @service.domains.exists?(hostname: hostname)
        return render json: { error: "Domain already exists" }, status: :unprocessable_entity
      end

      use_ssl = !server.magic_domain?
      target = @service.port || @service.detected_port || 80

      domain = @service.domains.create!(
        hostname: hostname,
        port: use_ssl ? 443 : 80,
        target_port: target,
        ssl: use_ssl,
        letsencrypt: use_ssl,
        temporary: true
      )

      # Sync to Dokku. Temporary magic domains never get TLS — only map https
      # when the domain actually supports SSL (non-magic domain).
      if server.ssh_key.present?
        engine = DokkuEngine.new(server)
        engine.domain_add(@service.dokku_app_name, hostname)
        engine.sync_port_mappings(@service.dokku_app_name, target, https: use_ssl)
      end

      render json: domain, status: :created
    rescue => e
      Rails.logger.error "generate_domain failed for #{@service.dokku_app_name}: #{e.message}"
      render json: { error: "Failed to generate domain: #{e.message}" }, status: :unprocessable_entity
    end

    private

    def set_and_authorize_service!
      @service = Service.find(params[:id] || params[:service_id])
      authorize_service!(@service)
    end

    # Helper to create DokkuEngine only when server has SSH key
    def with_dokku_engine(service)
      return unless service.project&.server&.ssh_key.present?
      engine = DokkuEngine.new(service.project.server)
      yield(engine)
    end

    # After Dokku links a database, it injects env vars like DATABASE_URL.
    # Fetch them from Dokku and sync into our DB so they appear in the UI.
    def sync_dokku_env_vars(engine, service)
      result = engine.config_show(service.dokku_app_name)
      return unless result[:success]

      # Parse Dokku config:show output — lines like "KEY: value"
      result[:output].each_line do |line|
        next unless line.include?(":")
        key, value = line.split(":", 2)
        next unless key && value
        key = key.strip
        value = value.strip

        # Only sync connection-string vars injected by Dokku plugins
        next unless key.match?(/^(DATABASE_URL|REDIS_URL|MONGO_URL|MYSQL_URL|DATABASE_PRIVATE_URL|REDIS_PRIVATE_URL)/i)

        service.environment_variables.find_or_initialize_by(key: key).tap do |ev|
          ev.value = value
          ev.is_dokku_internal = true
          ev.source = "dokku-link"
          ev.save!
        end
      end
    rescue => e
      Rails.logger.error "Failed to sync Dokku env vars for #{service.dokku_app_name}: #{e.message}"
    end

    # Remove env vars that were injected by a specific linked database.
    # We identify them by the dokku-link source and the connection URL pattern.
    def remove_linked_env_vars(service, target_db)
      service.environment_variables.where(is_dokku_internal: true, source: "dokku-link").destroy_all
    rescue => e
      Rails.logger.error "Failed to remove linked env vars for #{service.dokku_app_name}: #{e.message}"
    end

    # When an app is linked to a database/cache service, update the app's env vars
    # to use the linked service's alias hostname (e.g. redis, postgres) and sync
    # credentials from the linked service's env vars.
    def sync_linked_service_env_vars(engine, app_service, linked_service)
      alias_name = linked_service.name.to_s.downcase.gsub(/[^a-z0-9-]/, "-")

      # Update any app env var that matches known host patterns for this service name
      app_service.environment_variables.where(is_dokku_internal: false).find_each do |ev|
        next unless ev.value.present?

        # Patterns like: AP_REDIS_HOST, REDIS_HOST, POSTGRES_HOST, etc.
        # If the env var name contains the linked service name + HOST, update it
        if ev.key.match?(/#{linked_service.name.upcase.gsub(/[^A-Z0-9]/, '_')}_HOST/i)
          engine.config_set(app_service.dokku_app_name, ev.key, alias_name)
          ev.update!(value: alias_name)
        end
      end

      # Sync credentials from linked service's env vars to the app
      # e.g. if linked service has POSTGRES_PASSWORD, set AP_POSTGRES_PASSWORD
      linked_service.environment_variables.find_each do |src_ev|
        # Look for password/user/database env vars on the linked service
        next unless src_ev.key.match?(/^(POSTGRES|REDIS|MYSQL|MONGO)_(PASSWORD|USER|DATABASE|DB)/i)

        # Build the corresponding app env var key
        # e.g. POSTGRES_PASSWORD → AP_POSTGRES_PASSWORD
        prefix = Regexp.last_match(1) # POSTGRES, REDIS, etc.
        suffix = Regexp.last_match(2) # PASSWORD, USER, etc.

        # Find app env vars that reference this credential
        app_service.environment_variables.where(is_dokku_internal: false).find_each do |app_ev|
          if app_ev.key.match?(/#{prefix}_#{suffix}/i) && app_ev.value != src_ev.value
            engine.config_set(app_service.dokku_app_name, app_ev.key, src_ev.value)
            app_ev.update!(value: src_ev.value)
          end
        end
      end

      # For Dokku plugin-managed databases, also fetch the DSN and extract credentials
      if linked_service.service_type_database?
        fetch_and_sync_dsn_credentials(engine, app_service, linked_service)
      end
    rescue => e
      Rails.logger.error "Failed to sync linked env vars for #{app_service.dokku_app_name}: #{e.message}"
    end

    # Fetch DSN from Dokku plugin info and sync extracted credentials to the app
    def fetch_and_sync_dsn_credentials(engine, app_service, linked_service)
      st = linked_service.subtype_record
      return unless st&.has_capability?(:info)

      prefix = st.env_var_prefix&.then { |v| v.delete_suffix("_URL") } || st.subtype.upcase
      scheme = st.url_scheme

      if scheme == "redis"
        redis_url = linked_service.environment_variables.find_by(key: "REDIS_URL")&.value
        if redis_url.present?
          match = redis_url.match(/redis:\/\/(?<pass>[^@]+)@(?<host>[^:]+):(?<port>\d+)/)
          sync_credential_vars(engine, app_service, prefix, match) if match
        end
      else
        result = engine.datastore_info(linked_service)
        return unless result[:success]

        dsn_line = result[:output].lines.find { |l| l.match?(/Dsn:\s+\S+:\/\//) }
        return unless dsn_line

        match = dsn_line.match(/#{Regexp.escape(scheme)}:\/\/(?<user>[^:]+):(?<pass>[^@]+)@(?<host>[^:]+):(?<port>\d+)\/(?<db>\S+)/)
        return unless match

        sync_credential_vars(engine, app_service, prefix, match)
      end
    end

    # Update app env vars that match a given prefix (POSTGRES, REDIS, etc.)
    def sync_credential_vars(engine, app_service, prefix, match)
      mapping = {
        "user" => "#{prefix}_USERNAME",
        "pass" => "#{prefix}_PASSWORD",
        "host" => "#{prefix}_HOST",
        "port" => "#{prefix}_PORT",
        "db"   => "#{prefix}_DATABASE"
      }

      mapping.each do |key_suffix, env_suffix|
        value = match[key_suffix]
        next if value.blank?

        # Update any app env var that ends with this suffix
        app_service.environment_variables.where(is_dokku_internal: false).find_each do |ev|
          if ev.key.match?(/#{env_suffix}$/i) && ev.value != value
            engine.config_set(app_service.dokku_app_name, ev.key, value)
            ev.update!(value: value)
          end
        end
      end
    end

    def merge_config_overrides!
      return unless params[:service] && params[:service][:config].present?
      overrides = @service.config_overrides || {}
      incoming = params[:service][:config].to_unsafe_h
      overrides = overrides.deep_merge(incoming)
      @service.config_overrides = overrides
    end

    def service_params
      base_permitted = [
        :name, :service_type, :subtype, :status, :builder,
        :git_repo, :branch, :version, :exposed, :port,
        :locked, :restart_policy, :restart_max_retries,
        :docker_image, :auto_deploy, :root_directory,
        :start_command, :maintenance_mode,
        :canvas_x, :canvas_y,
        config: config_permitted_params,
        config_overrides: config_permitted_params
      ]
      params.require(:service).permit(base_permitted)
    rescue ActionController::ParameterMissing
      params.permit(base_permitted)
    end

    def config_permitted_params
      [
        :cron,
        proxy: [ :enabled, :proxyType, { portMappings: [ :scheme, :hostPort, :containerPort ] } ],
        dockerOptions: [ :phase, :option ],
        resourceLimits: [ :processType, :cpu, :memory, :memorySwap, :nvidiaGpu ],
        resourceReservations: [ :processType, :cpu, :memory, :memorySwap, :nvidiaGpu ],
        checks: [ :enabled, :mode, :wait, :timeout, :attempts, :waitToRetire, { skipList: [] } ],
        letsencrypt: [ :enabled, :email, :staging, :autoRenew ],
        git: [ :deployBranch, :keepGitDir, :revEnvVar ],
        traefik: [ :labels, :properties ]
      ]
    end

    def backup_schedule_params
      params.require(:backup_schedule).permit(:frequency, :retention_count, :backup_kind, :storage_mount_id, destination_ids: [])
            .tap { |p| p[:metadata] = { "destination_ids" => Array(p.delete(:destination_ids)).compact_blank } }
    end

  end
end
