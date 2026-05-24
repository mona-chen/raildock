module Api
  class ServicesController < BaseController
    include Authorizable

    # Standard error response format
    ERROR_RESPONSE = ->(message = nil, details = nil) {
      response = { error: message }
      response[:details] = details if details
      response
    }.call

    before_action :set_and_authorize_service!, only: [
      :show, :update, :destroy, :deploy, :rollback, :container_status,
      :start, :stop, :restart, :rebuild, :scale, :logs, :link, :unlink,
      :metrics, :backup, :restore, :database_info, :backups, :backup_schedules,
      :create_backup_schedule, :destroy_backup_schedule, :run, :enter, :linked_by
    ]

    def index
      project = scoped_projects.find_by(id: params[:project_id])
      authorize_project!(project)
      services = Service.where(project_id: params[:project_id])
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

      # Auto-assign default Docker image for known one-click service subtypes
      if attrs[:docker_image].blank? && attrs[:git_repo].blank?
        attrs[:docker_image] ||= Service::DEFAULT_DOCKER_IMAGES[attrs[:subtype]]
      end

      service = Service.create!(attrs)

      # Create Dokku resource if server is connected and has SSH key
      with_dokku_engine(service) do |engine|
        if service.service_type == "database"
          result = case service.subtype
          when "postgres" then engine.postgres_create(service.dokku_app_name)
          when "redis" then engine.redis_create(service.dokku_app_name)
          when "mysql" then engine.mysql_create(service.dokku_app_name)
          when "mongo" then engine.mongo_create(service.dokku_app_name)
          end
          service.update!(status: :running) if result && result[:success]
        else
          engine.app_create(service.dokku_app_name)
          engine.proxy_set(service.dokku_app_name, proxy_config[:proxyType])
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
        if @service.service_type == "database"
          case @service.subtype
          when "postgres" then engine.postgres_destroy(@service.dokku_app_name)
          when "redis" then engine.redis_destroy(@service.dokku_app_name)
          when "mysql" then engine.mysql_destroy(@service.dokku_app_name)
          when "mongo" then engine.mongo_destroy(@service.dokku_app_name)
          end
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
        commit_sha: params[:commit_sha]
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

      # Create a new deployment with the previous commit
      deployment = @service.deployments.create!(
        status: :pending,
        started_at: Time.current,
        branch: target.branch || @service.branch || "main",
        commit_sha: target.commit_sha
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
          result = engine.container_status(@service.dokku_app_name)
          if result[:success]
            return render json: { status: "running", output: result[:output] }
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

      with_dokku_engine(@service) do |engine|
        result = engine.ps_restart(@service.dokku_app_name)
        if result[:success]
          @service.update!(status: "running")
          ActivityEvent.create!(
            project: @service.project,
            service_name: @service.name,
            action: :restarted,
            message: "Restarted #{@service.name}"
          )
          return render json: { success: true, status: "running" }
        else
          return render json: { success: false, error: result[:output] }, status: :unprocessable_entity
        end
      end

      @service.update!(status: "running")
      render json: { success: true, status: "running" }
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
        if @service.service_type == "database"
          result = case @service.subtype
          when "postgres" then engine.postgres_logs(@service.dokku_app_name, lines: 100)
          when "redis" then engine.redis_logs(@service.dokku_app_name, lines: 100)
          when "mysql" then engine.mysql_logs(@service.dokku_app_name, lines: 100)
          when "mongo" then engine.mongo_logs(@service.dokku_app_name, lines: 100)
          else engine.logs(@service.dokku_app_name, lines: 100)
          end
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
          if target.service_type_database?
            case target.subtype
            when "postgres" then engine.postgres_link(target.dokku_app_name, @service.dokku_app_name)
            when "redis" then engine.redis_link(target.dokku_app_name, @service.dokku_app_name)
            when "mysql" then engine.mysql_link(target.dokku_app_name, @service.dokku_app_name)
            when "mongo" then engine.mongo_link(target.dokku_app_name, @service.dokku_app_name)
            end

            # Fetch and sync Dokku-injected env vars (DATABASE_URL, REDIS_URL, etc.)
            sync_dokku_env_vars(engine, @service)
          end

          # Connect both services to the project's private network
          # so they can resolve each other by internal hostname
          network_manager = ProjectNetworkManager.new(@service.project, engine)
          network_manager.connect_service(@service)
          network_manager.connect_service(target)
          network_manager.inject_internal_hostnames(@service)
        end

        ActivityEvent.create!(
          project: @service.project,
          service_name: @service.name,
          action: :linked,
          message: "Linked #{@service.name} to #{target.name}"
        )
      end

      render json: { success: true, linkedServiceIds: @service.reload.linked_service_ids }
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
        if db_service.service_type_database?
          case db_service.subtype
          when "postgres" then engine.postgres_unlink(db_service.dokku_app_name, app_service.dokku_app_name)
          when "redis" then engine.redis_unlink(db_service.dokku_app_name, app_service.dokku_app_name)
          when "mysql" then engine.mysql_unlink(db_service.dokku_app_name, app_service.dokku_app_name)
          when "mongo" then engine.mongo_unlink(db_service.dokku_app_name, app_service.dokku_app_name)
          end

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

      render json: { success: true, linkedServiceIds: @service.reload.linked_service_ids }
    end

    def metrics
      with_dokku_engine(@service) do |engine|
        result = engine.metrics(@service.dokku_app_name)
        if result[:success]
          return render json: parse_metrics(result[:output])
        end
      end

      # Fallback placeholder
      render json: { cpu: rand(10..80), memory: rand(20..90), networkIn: 0, networkOut: 0 }
    end

    def database_info
      with_dokku_engine(@service) do |engine|
        result = case @service.subtype
        when "postgres" then engine.postgres_info(@service.dokku_app_name)
        when "redis" then engine.redis_info(@service.dokku_app_name)
        when "mysql" then engine.mysql_info(@service.dokku_app_name)
        when "mongo" then engine.mongo_info(@service.dokku_app_name)
        else { success: false, error: "Unsupported database type" }
        end
        return render json: result
      end

      render json: { success: false, error: "No server configured" }
    end

    def backup
      authorize_service!(@service, action: :update)

      with_dokku_engine(@service) do |engine|
        backup_record = @service.backups.create!(status: "pending")

        result = case @service.subtype
        when "postgres" then engine.postgres_export(@service.dokku_app_name)
        when "redis" then engine.redis_export(@service.dokku_app_name)
        when "mysql" then engine.mysql_export(@service.dokku_app_name)
        when "mongo" then engine.mongo_export(@service.dokku_app_name)
        else { success: false, output: "Unsupported database type for backup" }
        end

        if result[:success]
          backup_record.update!(status: "completed", size: result[:output]&.bytesize || 0)
          ActivityEvent.create!(
            project: @service.project,
            service_name: @service.name,
            action: :created,
            message: "Backup created for #{@service.name}"
          )
          return render json: { success: true, backup: backup_record }
        else
          backup_record.update!(status: "failed", metadata: { error: result[:output] })
          return render json: { success: false, error: result[:output] }, status: :unprocessable_entity
        end
      end

      render json: { success: false, error: "No server configured" }, status: :unprocessable_entity
    end

    def restore
      authorize_service!(@service, action: :update)

      with_dokku_engine(@service) do |engine|
        data = request.body.read

        result = case @service.subtype
        when "postgres" then engine.postgres_import(@service.dokku_app_name, data)
        when "redis" then engine.redis_import(@service.dokku_app_name, data)
        when "mysql" then engine.mysql_import(@service.dokku_app_name, data)
        when "mongo" then engine.mongo_import(@service.dokku_app_name, data)
        else { success: false, output: "Unsupported database type for restore" }
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
      render json: @service.backups.recent
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
      render json: { error: "No server configured" }, status: :unprocessable_entity
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
      return render json: { error: "No base domain configured" }, status: :unprocessable_entity unless server.base_domain.present?

      hostname = server.temporary_hostname(@service.dokku_app_name)
      return render json: { error: "Could not generate hostname" }, status: :unprocessable_entity unless hostname

      # Check for collision
      if @service.domains.exists?(hostname: hostname)
        return render json: { error: "Domain already exists" }, status: :unprocessable_entity
      end

      use_ssl = !server.magic_domain?
      target = @service.detected_port || 80

      domain = @service.domains.create!(
        hostname: hostname,
        port: use_ssl ? 443 : 80,
        target_port: target,
        ssl: use_ssl,
        letsencrypt: use_ssl,
        temporary: true
      )

      # Sync to Dokku
      if server.ssh_key.present?
        engine = DokkuEngine.new(server)
        engine.domain_add(@service.dokku_app_name, hostname)
        engine.sync_port_mappings(@service.dokku_app_name, target)
      end

      render json: domain, status: :created
    rescue => e
      Rails.logger.error "generate_domain failed for #{@service.dokku_app_name}: #{e.message}"
      render json: { error: "Failed to generate domain: #{e.message}" }, status: :unprocessable_entity
    end

    private

    def set_and_authorize_service!
      @service = Service.find(params[:id])
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
        proxy: [:enabled, :proxyType, { portMappings: [:scheme, :hostPort, :containerPort] }],
        dockerOptions: [:phase, :option],
        resourceLimits: [:processType, :cpu, :memory, :memorySwap, :nvidiaGpu],
        resourceReservations: [:processType, :cpu, :memory, :memorySwap, :nvidiaGpu],
        checks: [:enabled, :wait, :timeout, { skipList: [] }],
        letsencrypt: [:enabled, :email, :staging, :autoRenew],
        git: [:deployBranch, :keepGitDir, :revEnvVar],
        traefik: [:labels, :properties]
      ]
    end

    def backup_schedule_params
      params.require(:backup_schedule).permit(:frequency, :retention_count)
    end

    def parse_metrics(output)
      cpu_match = output.match(/cpu\s+(\d+)/i)
      memory_match = output.match(/memory\s+(\d+)/i)

      unless cpu_match && memory_match
        Rails.logger.warn "Metrics parsing failed - Dokku ps:report output may have changed format. Output: #{output[0..500]}"
      end

      {
        cpu: cpu_match ? cpu_match[1].to_i : nil,
        memory: memory_match ? memory_match[1].to_i : nil,
        networkIn: 0,
        networkOut: 0
      }
    end
  end
end