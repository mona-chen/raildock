module Api
  module V1
    class ContextController < BaseController
      def show
        return unless require_scope!(:read)

        projects = scoped_projects.includes(:environments, services: :domains).order(:name)

        render json: ContextPresenter.new(
          organization: current_organization,
          projects: projects,
          servers: scoped_servers.order(:name),
          role: current_role,
          token: current_api_token,
          user: current_user
        ).as_json
      end
    end
  end
end
