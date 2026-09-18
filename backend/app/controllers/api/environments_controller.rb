module Api
  class EnvironmentsController < BaseController
    include Authorizable

    before_action :set_project

    def index
      authorize_project!(@project)
      render json: @project.environments.ordered
    end

    def create
      authorize_project!(@project, action: :update)
      environment = @project.environments.create!(environment_params)
      render json: environment, status: :created
    end

    def update
      authorize_project!(@project, action: :update)
      environment = @project.environments.find(params[:id])
      environment.update!(environment_params)
      sync_primary_label(environment)
      render json: environment
    end

    # Refused for the default environment and for any environment that still
    # owns services, so switching environments can never orphan a running app.
    def destroy
      authorize_project!(@project, action: :delete)
      environment = @project.environments.find(params[:id])
      environment.destroy!
      head :no_content
    rescue ActiveRecord::RecordNotDestroyed => e
      message = e.record&.errors&.full_messages&.join("; ").presence || e.message
      render json: { error: message, code: "environment_guarded" }, status: :unprocessable_entity
    end

    private
      def set_project
        @project = scoped_projects.find(params[:project_id])
      end

      def environment_params
        params.require(:environment).permit(:name, :description)
      end

      # The projects list still labels each project with `project.environment`,
      # so keep that label pointing at the default environment's name.
      def sync_primary_label(environment)
        return unless environment.is_default?
        return if @project.environment == environment.name

        @project.update_column(:environment, environment.name)
      end
  end
end
