module Api
  class EnvironmentsController < BaseController
    include Authorizable

    before_action :set_project
    before_action :set_environment, only: [ :duplicate, :sync_plan, :sync ]

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

    # Copies every service and its configuration into a new environment. The
    # copies are staged (never deployed, never created on the Dokku host), which
    # is why this is a single request instead of a deploy-time side effect.
    def duplicate
      authorize_project!(@project, action: :create)

      result = EnvironmentDuplicator.new(
        @environment,
        name: environment_params[:name],
        description: environment_params[:description]
      ).call

      if result.environment.nil?
        return render json: { error: result.summary[:warnings].first, code: "name_required" },
          status: :unprocessable_entity
      end

      render json: { environment: result.environment, summary: result.summary }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join("; "), code: "invalid_environment" },
        status: :unprocessable_entity
    end

    # Read-only review of what a sync would change. Nothing is written here, so
    # the UI can stage the changes and let the operator accept them.
    def sync_plan
      authorize_project!(@project, action: :update)
      source = source_environment or return render_source_error

      render json: EnvironmentDiff.new(source: source, target: @environment).call
    end

    # Adds services the target is missing and updates the ones that drifted.
    # Deliberately never deletes: services that exist only in this environment
    # are reported so they can be removed through the guarded destroy endpoint.
    def sync
      authorize_project!(@project, action: :update)
      source = source_environment or return render_source_error

      result = EnvironmentSync.new(source: source, target: @environment).call

      render json: {
        plan: result.plan,
        applied: {
          added: result.added.map { |service| { id: service.id, name: service.name } },
          updated: result.updated.map { |service| { id: service.id, name: service.name } },
          removed: result.removed.map { |entry| { id: entry.service_id, name: entry.name } }
        },
        message: result.message
      }
    end

    private
      def set_project
        @project = scoped_projects.find(params[:project_id])
      end

      def set_environment
        @environment = @project.environments.find(params[:id])
      end

      def environment_params
        params.require(:environment).permit(:name, :description)
      end

      # The environment a sync pulls from. It must live in the same project:
      # syncing across projects would move configuration between two different
      # Dokku hosts and two different sets of variables.
      def source_environment
        id = params[:source_environment_id].presence
        return nil if id.blank?
        return nil if id.to_s == @environment.id.to_s

        @project.environments.find_by(id: id)
      end

      def render_source_error
        render json: {
          error: "source_environment_id must name another environment in this project",
          code: "invalid_source_environment"
        }, status: :unprocessable_entity
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
