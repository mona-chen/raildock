module Api
  class ProjectsController < BaseController
    def index
      projects = Project.includes(:services).all
      render json: projects.as_json(methods: [:service_ids])
    end

    def show
      project = Project.find(params[:id])
      render json: project.as_json(
        methods: [:service_ids],
        include: { services: { only: [:id, :name, :service_type, :subtype, :status] } }
      )
    end

    def create
      project = Project.new(project_params)
      project.server ||= Server.first
      project.save!
      ActivityEvent.create!(project: project, service_name: "-", action: :created, message: "Project #{project.name} created")
      render json: project, status: :created
    end

    def destroy
      project = Project.find(params[:id])
      project.destroy!
      head :no_content
    end

    def shared_vars
      project = Project.find(params[:id])
      project.update!(shared_vars: params[:vars] || [])
      render json: project
    end

    def activity
      project = Project.find(params[:id])
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
