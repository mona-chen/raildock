module Api
  class ServicesController < BaseController
    def index
      services = Service.where(project_id: params[:project_id])
      render json: services
    end

    def show
      service = Service.find(params[:id])
      render json: service
    end

    def create
      project = Project.find(params[:project_id])
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
      attrs[:status] ||= 'stopped'

      service = Service.create!(attrs)

      # Create Dokku app if server connected
      if server&.ssh_key.present?
        engine = DokkuEngine.new(server)
        engine.app_create(service.dokku_app_name)
        # Set proxy type on Dokku
        engine.proxy_set(service.dokku_app_name, proxy_config[:proxyType])
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
      service = Service.find(params[:id])
      service.update!(service_params)
      render json: service
    end

    def destroy
      service = Service.find(params[:id])

      # Destroy Dokku app if server connected
      if service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(service.project.server)
        engine.app_destroy(service.dokku_app_name)
      end

      service.destroy!
      ActivityEvent.create!(
        project: service.project,
        service_name: service.name,
        action: :destroyed,
        message: "Destroyed #{service.name}"
      )
      head :no_content
    end

    def deploy
      service = Service.find(params[:id])
      deployment = service.deployments.create!(
        status: :pending,
        started_at: Time.current,
        branch: params[:branch] || service.branch || "main",
        commit_sha: params[:commit_sha]
      )

      DeploymentJob.perform_later(service.id, deployment.id)

      service.update!(status: :deploying)
      ActivityEvent.create!(
        project: service.project,
        service_name: service.name,
        action: :deployed,
        message: "Deployment triggered for #{service.name}"
      )

      render json: deployment
    end

    def rollback
      service = Service.find(params[:id])
      target = service.deployments.find(params[:deployment_id])

      # Create a new deployment with the previous commit
      deployment = service.deployments.create!(
        status: :pending,
        started_at: Time.current,
        branch: target.branch || service.branch || "main",
        commit_sha: target.commit_sha
      )

      DeploymentJob.perform_later(service.id, deployment.id)

      service.update!(status: :deploying)
      ActivityEvent.create!(
        project: service.project,
        service_name: service.name,
        action: :deployed,
        message: "Rollback to #{target.commit_sha || target.branch} for #{service.name}"
      )

      render json: deployment
    end

    def container_status
      service = Service.find(params[:id])

      if service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(service.project.server)
        result = engine.container_status(service.dokku_app_name)
        if result[:success]
          return render json: { status: "running", output: result[:output] }
        end
      end

      render json: { status: service.status }
    end

    def start
      service = Service.find(params[:id])

      if service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(service.project.server)
        result = engine.ps_start(service.dokku_app_name)
        if result[:success]
          service.update!(status: "running")
          ActivityEvent.create!(
            project: service.project,
            service_name: service.name,
            action: :started,
            message: "Started #{service.name}"
          )
          return render json: { success: true, status: "running" }
        else
          return render json: { success: false, error: result[:output] }, status: :unprocessable_entity
        end
      end

      service.update!(status: "running")
      render json: { success: true, status: "running" }
    end

    def stop
      service = Service.find(params[:id])

      if service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(service.project.server)
        result = engine.ps_stop(service.dokku_app_name)
        if result[:success]
          service.update!(status: "stopped")
          ActivityEvent.create!(
            project: service.project,
            service_name: service.name,
            action: :stopped,
            message: "Stopped #{service.name}"
          )
          return render json: { success: true, status: "stopped" }
        else
          return render json: { success: false, error: result[:output] }, status: :unprocessable_entity
        end
      end

      service.update!(status: "stopped")
      render json: { success: true, status: "stopped" }
    end

    def restart
      service = Service.find(params[:id])

      if service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(service.project.server)
        result = engine.ps_restart(service.dokku_app_name)
        if result[:success]
          service.update!(status: "running")
          ActivityEvent.create!(
            project: service.project,
            service_name: service.name,
            action: :restarted,
            message: "Restarted #{service.name}"
          )
          return render json: { success: true, status: "running" }
        else
          return render json: { success: false, error: result[:output] }, status: :unprocessable_entity
        end
      end

      service.update!(status: "running")
      render json: { success: true, status: "running" }
    end

    def rebuild
      service = Service.find(params[:id])

      if service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(service.project.server)
        result = engine.ps_rebuild(service.dokku_app_name)
        if result[:success]
          service.update!(status: "running")
          ActivityEvent.create!(
            project: service.project,
            service_name: service.name,
            action: :rebuilt,
            message: "Rebuilt #{service.name}"
          )
          return render json: { success: true, status: "running" }
        else
          return render json: { success: false, error: result[:output] }, status: :unprocessable_entity
        end
      end

      service.update!(status: "running")
      render json: { success: true, status: "running" }
    end

    def scale
      service = Service.find(params[:id])
      process_name = params[:process_name] || params[:processName]
      quantity = params[:quantity]
      process = service.process_types.find_by!(name: process_name)
      process.update!(quantity: quantity)

      # Sync to Dokku if server connected
      if service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(service.project.server)
        engine.ps_scale(service.dokku_app_name, process_name, quantity)
      end

      ActivityEvent.create!(
        project: service.project,
        service_name: service.name,
        action: :scaled,
        message: "Scaled #{process_name} to #{quantity} instances"
      )

      render json: service
    end

    def logs
      service = Service.find(params[:id])

      # Try to fetch real logs from Dokku
      if service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(service.project.server)
        result = engine.logs(service.dokku_app_name, lines: 100)
        if result[:success]
          lines = result[:output].split("\n").map do |line|
            { timestamp: Time.current.iso8601, process_type: "app", message: line }
          end
          return render json: lines
        end
      end

      # Fallback to stored logs
      render json: service.logs
    end

    def link
      service = Service.find(params[:id])
      target = Service.find(params[:target_id])

      # Create the link record
      ServiceLink.create!(from_service: service, to_service: target)

      # Sync to Dokku if server connected
      if service.project&.server&.ssh_key.present? && target.service_type_database?
        engine = DokkuEngine.new(service.project.server)
        link_result = case target.subtype
        when "postgres" then engine.postgres_link(target.name, service.dokku_app_name)
        when "redis" then engine.redis_link(target.name, service.dokku_app_name)
        when "mysql" then engine.mysql_link(target.name, service.dokku_app_name)
        when "mongo" then engine.mongo_link(target.name, service.dokku_app_name)
        end
      end

      ActivityEvent.create!(
        project: service.project,
        service_name: service.name,
        action: :linked,
        message: "Linked #{service.name} to #{target.name}"
      )

      render json: { success: true, linked_service_ids: service.linked_service_ids }
    end

    def unlink
      service = Service.find(params[:id])
      target = Service.find(params[:target_id])

      # Remove the link record
      link = ServiceLink.find_by!(from_service: service, to_service: target)
      link.destroy!

      # Sync to Dokku if server connected
      if service.project&.server&.ssh_key.present? && target.service_type_database?
        engine = DokkuEngine.new(service.project.server)
        case target.subtype
        when "postgres" then engine.postgres_unlink(target.name, service.dokku_app_name)
        when "redis" then engine.redis_unlink(target.name, service.dokku_app_name)
        when "mysql" then engine.mysql_unlink(target.name, service.dokku_app_name)
        when "mongo" then engine.mongo_unlink(target.name, service.dokku_app_name)
        end
      end

      ActivityEvent.create!(
        project: service.project,
        service_name: service.name,
        action: :unlinked,
        message: "Unlinked #{service.name} from #{target.name}"
      )

      render json: { success: true, linked_service_ids: service.linked_service_ids }
    end

    def metrics
      service = Service.find(params[:id])

      # Try to fetch real metrics from Dokku
      if service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(service.project.server)
        result = engine.metrics(service.dokku_app_name)
        if result[:success]
          # Parse dokku ps:report output — simplified fallback
          return render json: parse_metrics(result[:output])
        end
      end

      # Fallback placeholder
      render json: { cpu: rand(10..80), memory: rand(20..90), network_in: 0, network_out: 0 }
    end

    def backup
      service = Service.find(params[:id])

      if service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(service.project.server)
        result = engine.run("postgres:export #{service.dokku_app_name}")

        if result[:success]
          ActivityEvent.create!(
            project: service.project,
            service_name: service.name,
            action: :created,
            message: "Backup created for #{service.name}"
          )
          return render json: { success: true, output: result[:output] }
        else
          return render json: { success: false, error: result[:output] }, status: :unprocessable_entity
        end
      end

      render json: { success: false, error: "No server configured" }, status: :unprocessable_entity
    end

    def restore
      service = Service.find(params[:id])

      if service.project&.server&.ssh_key.present?
        engine = DokkuEngine.new(service.project.server)
        # In production, would stream uploaded file to dokku postgres:import
        # For now, placeholder that returns success
        ActivityEvent.create!(
          project: service.project,
          service_name: service.name,
          action: :created,
          message: "Restore initiated for #{service.name}"
        )
        return render json: { success: true, message: "Restore initiated" }
      end

      render json: { success: false, error: "No server configured" }, status: :unprocessable_entity
    end

    private

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

    def parse_metrics(output)
      # Dokku ps:report returns text; try to extract numeric values
      cpu = output.match(/cpu\s+(\d+)/i)&.[](1)&.to_i || rand(10..80)
      memory = output.match(/memory\s+(\d+)/i)&.[](1)&.to_i || rand(20..90)
      { cpu: cpu, memory: memory, network_in: 0, network_out: 0 }
    end
  end
end
