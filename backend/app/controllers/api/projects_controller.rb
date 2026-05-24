module Api
  class ProjectsController < BaseController
    include Authorizable

    def index
      authorize_project!(nil, action: :read) # Check user has org access
      projects = scoped_projects.includes(:services)
      render json: projects.as_json(methods: [:service_ids, :service_counts])
    end

    def show
      project = scoped_projects.find(params[:id])
      authorize_project!(project)
      render json: project.as_json(
        methods: [:service_ids, :service_counts],
        include: { services: { only: [:id, :name, :service_type, :subtype, :status] } }
      )
    end

    def create
      authorize_project!(nil, action: :create)
      project = Project.new(project_params)
      project.organization = current_organization
      project.server ||= Server.first
      project.save!
      ActivityEvent.create!(project: project, service_name: "-", action: :created, message: "Project #{project.name} created")
      render json: project, status: :created
    end

    def update
      project = scoped_projects.find(params[:id])
      authorize_project!(project, action: :update)
      project.update!(project_params)
      render json: project.as_json(methods: [:service_ids, :service_counts])
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
      project.update!(shared_vars: params[:vars] || [])
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

      services = project.services.where.not(service_type: "database")
      results = []

      services.each do |service|
        deployment = service.deployments.create!(
          status: :pending,
          started_at: Time.current,
          branch: service.branch || "main"
        )
        DeploymentJob.perform_later(service.id, deployment.id)
        service.update!(status: :deploying)
        results << service.name
      end

      ActivityEvent.create!(
        project: project, service_name: "-", action: :deployed,
        message: "Deployed all apps in #{project.name} (#{results.length} services)"
      )

      render json: { queued: results.length, services: results }
    end

    def restart_all
      project = scoped_projects.find(params[:id])
      authorize_project!(project, action: :update)

      queued = []
      project.services.each do |service|
        RestartJob.perform_later(service.id)
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

    def project_params
      params.require(:project).permit(:name, :description, :environment, :server_id)
    rescue ActionController::ParameterMissing
      params.permit(:name, :description, :environment, :server_id)
    end

    def with_dokku_engine(service)
      return unless service.project&.server&.ssh_key.present?
      engine = DokkuEngine.new(service.project.server)
      yield(engine)
    end
  end
end