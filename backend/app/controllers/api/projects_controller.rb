module Api
  class ProjectsController < BaseController
    include Authorizable

    def index
      authorize_project!(nil, action: :read) # Check user has org access
      projects = scoped_projects.includes(:services)
      render json: projects.as_json(methods: [ :service_ids, :service_counts ])
    end

    def show
      project = scoped_projects.find(params[:id])
      authorize_project!(project)
      render json: project.as_json(
        methods: [ :service_ids, :service_counts ],
        include: { services: { only: [ :id, :name, :service_type, :subtype, :status ] } }
      )
    end

    def create
      authorize_project!(nil, action: :create)
      project = Project.new(project_params)
      project.organization = current_organization
      project.user = current_user unless current_organization
      project.server ||= scoped_servers.first
      project.save!
      ActivityEvent.create!(project: project, service_name: "-", action: :created, message: "Project #{project.name} created")
      render json: project, status: :created
    end

    def update
      project = scoped_projects.find(params[:id])
      authorize_project!(project, action: :update)
      project.update!(project_params)
      render json: project.as_json(methods: [ :service_ids, :service_counts ])
    end

    def destroy
      project = scoped_projects.find(params[:id])
      authorize_project!(project, action: :delete)
      project.destroy!
      head :no_content
    end

    def shared_vars
      project = scoped_projects.find(params[:id])
      authorize_project!(project, action: :update)
      project.update!(shared_vars: params[:vars] || params.dig(:project, :vars) || [])
      render json: project
    end

    def activity
      project = scoped_projects.find(params[:id])
      authorize_project!(project)
      events = project.activity_events.limit(50)
      render json: events
    end

    def deploy_all
      project = scoped_projects.find(params[:id])
      authorize_project!(project, action: :update)

      services = project.services.where.not(service_type: "database").to_a
      sorted = topo_sort_by_depends_on(services)
      results = []
      deployments_by_service = {}

      sorted.each do |service|
        deployment = service.deployments.create!(
          status: :pending,
          started_at: Time.current,
          branch: service.branch || "main"
        )
        deployments_by_service[service.id] = deployment
        service.update!(status: :deploying)
        results << service.name
      end

      ids_by_name = sorted.index_by(&:name).transform_values(&:id)
      entries = sorted.map do |service|
        dependency_ids = Array(service.config&.dig("depends_on")).filter_map do |name|
          deployments_by_service[ids_by_name[name]]&.id
        end
        {
          service_id: service.id,
          deployment_id: deployments_by_service.fetch(service.id).id,
          depends_on_deployment_ids: dependency_ids
        }
      end
      DeploymentSequenceJob.perform_later(entries)

      ActivityEvent.create!(
        project: project, service_name: "-", action: :deployed,
        message: "Deployed all apps in #{project.name} (#{results.length} services)"
      )

      render json: { queued: results.length, services: results }
    end

    def cancel_deployments
      project = scoped_projects.find(params[:id])
      authorize_project!(project, action: :update)

      deployments = Deployment.cancellable.joins(:service).where(services: { project_id: project.id }).to_a
      cancelled = deployments.count { |deployment| deployment.cancel!(message: "Cancelled from project actions") }

      render json: { cancelled: cancelled }
    end

    def restart_all
      project = scoped_projects.find(params[:id])
      authorize_project!(project, action: :update)

      services = project.services.to_a
      sorted = topo_sort_by_depends_on(services)
      queued = []

      sorted.each do |service|
        next if service.project&.server&.ssh_key.blank?

        idempotency_key = "restart-all:#{project.id}:#{service.id}:#{params[:nonce] || Time.current.to_f}"
        RestartJob.perform_later(service.id, idempotency_key: idempotency_key)
        queued << service.name
      end

      ActivityEvent.create!(
        project: project, service_name: "-", action: :restarted,
        message: "Restart queued for #{queued.length} services in #{project.name}"
      )

      render json: { queued: queued.length, services: queued }
    end

    def stop_all
      project = scoped_projects.find(params[:id])
      authorize_project!(project, action: :update)

      results = { success: [], failed: [] }

      project.services.each do |service|
        with_dokku_engine(service) do |engine|
          result = engine.ps_stop(service.dokku_app_name)
          if result[:success]
            service.update!(status: "stopped")
            results[:success] << service.name
          else
            results[:failed] << { name: service.name, error: result[:output] }
          end
        end
      end

      ActivityEvent.create!(
        project: project, service_name: "-", action: :stopped,
        message: "Stopped all services in #{project.name}"
      )

      render json: results
    end

    private

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

    def project_params
      params.require(:project).permit(:name, :description, :environment, :server_id).tap do |permitted|
        permitted.delete(:server_id) if permitted[:server_id].present? && !scoped_servers.exists?(id: permitted[:server_id])
      end
    rescue ActionController::ParameterMissing
      params.permit(:name, :description, :environment, :server_id).tap do |permitted|
        permitted.delete(:server_id) if permitted[:server_id].present? && !scoped_servers.exists?(id: permitted[:server_id])
      end
    end

    def with_dokku_engine(service)
      return unless service.project&.server&.ssh_key.present?
      engine = DokkuEngine.new(service.project.server)
      yield(engine)
    end
  end
end
