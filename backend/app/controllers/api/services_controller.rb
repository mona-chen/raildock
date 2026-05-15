module Api
  class ServicesController < BaseController
    include Authorizable
    before_action :set_and_authorize_service!, only: [
      :show, :update, :destroy, :deploy, :rollback, :container_status,
      :start, :stop, :restart, :rebuild, :scale, :logs, :link, :unlink,
      :metrics, :backup, :restore, :database_info, :backups, :backup_schedules,
      :create_backup_schedule, :destroy_backup_schedule, :run, :enter
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

      service = Service.create!(attrs)

      # Create Dokku resource if server connected
      if server&.ssh_key.present?
        engine = DokkuEngine.new(server)
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
      @service.update!(service_params)
      render json: @service
    end

    def destroy
      # Destroy Dokku resource if server connected
      if @service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(@service.project.server)
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
      if @service.service_type == "database"
        render json: { error: "Database services cannot be deployed. They are managed directly by Dokku." }, status: :unprocessable_entity
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
      if @service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(@service.project.server)
        result = engine.container_status(@service.dokku_app_name)
        if result[:success]
          return render json: { status: "running", output: result[:output] }
        end
      end

      render json: { status: @service.status }
    end

    def start
      if @service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(@service.project.server)
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
      if @service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(@service.project.server)
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
      if @service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(@service.project.server)
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
      if @service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(@service.project.server)
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
      process_name = params[:process_name] || params[:processName]
      quantity = params[:quantity]
      process = @service.process_types.find_by!(name: process_name)
      process.update!(quantity: quantity)

      # Sync to Dokku if server connected
      if @service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(@service.project.server)
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
      if @service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(@service.project.server)

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
            { timestamp: Time.current.iso8601, process_type: @service.subtype, message: line }
          end
          return render json: lines
        end
      end

      # Fallback to stored logs
      render json: @service.logs
    end

    def link
      target = Service.find(params[:target_id])
      authorize_service!(target)

      # Create the link record
      ServiceLink.create!(from_service: @service, to_service: target)

      # Sync to Dokku if server connected
      if @service.project&.server&.ssh_key.present? && target.service_type_database?
        engine = DokkuEngine.new(@service.project.server)
        case target.subtype
        when "postgres" then engine.postgres_link(target.name, @service.dokku_app_name)
        when "redis" then engine.redis_link(target.name, @service.dokku_app_name)
        when "mysql" then engine.mysql_link(target.name, @service.dokku_app_name)
        when "mongo" then engine.mongo_link(target.name, @service.dokku_app_name)
        end
      end

      ActivityEvent.create!(
        project: @service.project,
        service_name: @service.name,
        action: :linked,
        message: "Linked #{@service.name} to #{target.name}"
      )

      render json: { success: true, linked_service_ids: @service.linked_service_ids }
    end

    def unlink
      target = Service.find(params[:target_id])
      authorize_service!(target)

      # Remove the link record
      link = ServiceLink.find_by!(from_service: @service, to_service: target)
      link.destroy!

      # Sync to Dokku if server connected
      if @service.project&.server&.ssh_key.present? && target.service_type_database?
        engine = DokkuEngine.new(@service.project.server)
        case target.subtype
        when "postgres" then engine.postgres_unlink(target.name, @service.dokku_app_name)
        when "redis" then engine.redis_unlink(target.name, @service.dokku_app_name)
        when "mysql" then engine.mysql_unlink(target.name, @service.dokku_app_name)
        when "mongo" then engine.mongo_unlink(target.name, @service.dokku_app_name)
        end
      end

      ActivityEvent.create!(
        project: @service.project,
        service_name: @service.name,
        action: :unlinked,
        message: "Unlinked #{@service.name} from #{target.name}"
      )

      render json: { success: true, linked_service_ids: @service.linked_service_ids }
    end

    def metrics
      # Try to fetch real metrics from Dokku
      if @service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(@service.project.server)
        result = engine.metrics(@service.dokku_app_name)
        if result[:success]
          # Parse dokku ps:report output — simplified fallback
          return render json: parse_metrics(result[:output])
        end
      end

      # Fallback placeholder
      render json: { cpu: rand(10..80), memory: rand(20..90), network_in: 0, network_out: 0 }
    end

    def database_info
      if @service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(@service.project.server)
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
      if @service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(@service.project.server)
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
      if @service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(@service.project.server)
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
      schedule = @service.backup_schedules.create!(backup_schedule_params)
      schedule.update_next_run!
      render json: schedule, status: :created
    end

    def destroy_backup_schedule
      schedule = @service.backup_schedules.find(params[:schedule_id])
      schedule.destroy!
      head :no_content
    end

    def run
      command = params[:command]
      unless command.present?
        return render json: { error: "Command is required" }, status: :unprocessable_entity
      end

      if @service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(@service.project.server)
        result = engine.run_one_off(@service.dokku_app_name, command)
        return render json: { success: result[:success], output: result[:output] }
      end

      render json: { error: "No server configured" }, status: :unprocessable_entity
    end

    def enter
      process_type = params[:process_type] || "web"

      if @service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(@service.project.server)
        result = engine.enter_container(@service.dokku_app_name, process_type: process_type)
        return render json: { success: result[:success], output: result[:output] }
      end

      render json: { error: "No server configured" }, status: :unprocessable_entity
    end

    def config_show
      project = scoped_projects.find_by(id: params[:project_id])
      authorize_project!(project)
      service = Service.find(params[:service_id])
      authorize_service!(service)

      if service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(service.project.server)
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

      if service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(service.project.server)
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

      if service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(service.project.server)
        result = engine.storage_list(service.dokku_app_name)
        return render json: { success: result[:success], output: result[:output] }
      end

      render json: { error: "No server configured" }, status: :unprocessable_entity
    end

    private

    def set_and_authorize_service!
      @service = Service.find(params[:id])
      authorize_service!(@service)
    end

    def service_params
      params.require(:service).permit(
        :name, :service_type, :subtype, :status, :builder,
        :git_repo, :branch, :version, :exposed, :port,
        :locked, :restart_policy, :restart_max_retries,
        :docker_image,
        config: {}
      )
    rescue ActionController::ParameterMissing
      params.permit(
        :name, :service_type, :subtype, :status, :builder,
        :git_repo, :branch, :version, :exposed, :port,
        :locked, :restart_policy, :restart_max_retries,
        :docker_image,
        config: {}
      )
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
        cpu: cpu_match&.[](1)&.to_i,
        memory: memory_match&.[](1)&.to_i,
        network_in: 0,
        network_out: 0
      }
    end
  end
end
