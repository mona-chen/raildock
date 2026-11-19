module Api
  class ProjectsController < BaseController
    include Authorizable
    around_action :serialize_project_operation, only: [ :destroy, :stop_all ]

    def index
      authorize_project!(nil, action: :read) # Check user has org access
      # Project#as_json owns the serialized shape (including has_deployments and
      # the environment list); passing `methods:` here is ignored, not merged.
      projects = scoped_projects.includes(:services, environments: :services)
      render json: projects
    end

    def show
      project = scoped_projects.includes(environments: :services).find(params[:id])
      authorize_project!(project)
      render json: project.as_json(
        include: { services: { only: [ :id, :name, :service_type, :subtype, :status, :environment_id ] } }
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

    # Destroys a project *and* every Dokku app, datastore, and volume it owns.
    # Requires the caller to type the project name, and refuses to continue
    # unless every data-bearing service could be snapshotted first.
    def destroy
      project = scoped_projects.find(params[:id])
      authorize_project!(project, action: :delete)

      unless params[:confirmation].to_s == project.name
        return render json: {
          error: "Type the project name to confirm deletion of #{project.name} and everything it owns",
          code: "confirmation_required",
          actionable: true,
          project: project.dokku_resource_summary
        }, status: :precondition_required
      end

      # Repeated requests attach to the existing operation instead of deleting twice.
      if project.deletion_pending?
        operation = project_deletion_operation(project)
        return render json: { status: project.deletion_status, operation_id: operation&.id&.to_s }, status: :accepted
      end

      project.update!(deletion_status: "queued", deletion_error: nil, deletion_error_code: nil, deletion_requested_at: Time.current)
      operation = create_project_deletion_operation(project)
      begin
        ProjectDeletionJob.perform_later(project.id, force_destroy_data: force_destroy_data?)
      rescue StandardError
        project.update!(deletion_status: "failed", deletion_error: "Could not queue deletion. Please retry.")
        operation&.update!(status: "failed", error: "Could not queue deletion. Please retry.", completed_at: Time.current)
        raise
      end
      render json: { status: "queued", operation_id: operation&.id&.to_s }, status: :accepted
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

      services = bulk_services(project).where(service_type: "app").to_a
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

      deployments = Deployment.cancellable.where(service_id: bulk_services(project).select(:id)).to_a
      cancelled = deployments.count { |deployment| deployment.cancel!(message: "Cancelled from project actions") }

      render json: { cancelled: cancelled }
    end

    def restart_all
      project = scoped_projects.find(params[:id])
      authorize_project!(project, action: :update)

      services = bulk_services(project).to_a
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

      bulk_services(project).each do |service|
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

    # Absence means the default environment, never every environment.
    def serialize_project_operation
      project = scoped_projects.find(params[:id])
      authorize_project!(project, action: action_name == "destroy" ? :delete : :update)
      if action_name == "destroy" && project.deletion_pending?
        yield
      else
        ServiceOperationLock.with_project(project, exclusive: true, allow_deletion: action_name == "destroy") { yield }
      end
    end

    def bulk_services(project)
      environment = params[:environment_id].present? ? project.environments.find(params[:environment_id]) : project.default_environment
      project.services.where(environment: environment)
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

    def project_params
      params.require(:project).permit(:name, :description, :environment, :server_id).tap do |permitted|
        permitted.delete(:server_id) if permitted[:server_id].present? && !scoped_servers.exists?(id: permitted[:server_id])
      end
    rescue ActionController::ParameterMissing
      params.permit(:name, :description, :environment, :server_id).tap do |permitted|
        permitted.delete(:server_id) if permitted[:server_id].present? && !scoped_servers.exists?(id: permitted[:server_id])
      end
    end

    def force_destroy_data?
      ActiveModel::Type::Boolean.new.cast(params[:force_destroy_data]) || false
    end

    # A deletion is queued, not executed, so the caller polls an operation
    # instead of waiting for the request. Personal projects have no
    # organization to scope an operation to, so they keep the bare status.
    def project_deletion_operation(project)
      return unless project.organization

      Operation.where(kind: "project_deletion", subject_type: "Project", subject_id: project.id).order(:id).last
    end

    def create_project_deletion_operation(project)
      return unless project.organization

      Operation.create!(
        organization: project.organization,
        project: project,
        kind: "project_deletion",
        subject: project,
        api_token: current_api_token
      )
    end

    def with_dokku_engine(service)
      return unless service.project&.server&.ssh_key.present?
      engine = DokkuEngine.new(service.project.server)
      yield(engine)
    end
  end
end
