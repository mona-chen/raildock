module Api
  class ProjectsController < BaseController
    include Authorizable

    def index
      projects = scoped_projects.includes(:services)
      render json: projects.as_json(methods: [:service_ids, :service_counts])
    end

    def show
      project = scoped_projects.find(params[:id])
      render json: project.as_json(
        methods: [:service_ids, :service_counts],
        include: { services: { only: [:id, :name, :service_type, :subtype, :status] } }
      )
    end

    def create
      project = Project.new(project_params)
      project.organization = current_organization
      project.server ||= Server.first
      project.save!
      ActivityEvent.create!(project: project, service_name: "-", action: :created, message: "Project #{project.name} created")
      render json: project, status: :created
    end

    def update
      project = scoped_projects.find(params[:id])
      project.update!(project_params)
      render json: project.as_json(methods: [:service_ids, :service_counts])
    end

    def destroy
      project = scoped_projects.find(params[:id])
      project.destroy!
      head :no_content
    end

    def shared_vars
      project = scoped_projects.find(params[:id])
      project.update!(shared_vars: params[:vars] || [])
      render json: project
    end

    def activity
      project = scoped_projects.find(params[:id])
      events = project.activity_events.limit(50)
      render json: events
    end

    private

    def project_params
      params.require(:project).permit(:name, :description, :environment, :server_id)
    rescue ActionController::ParameterMissing
      params.permit(:name, :description, :environment, :server_id)
    end
  end
end
