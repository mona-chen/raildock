module Api
  module V1
    class ProjectsController < BaseController
      def show
        return unless require_scope!(:read)

        project = scoped_projects.includes(:environments, services: [ :domains, :environment ]).find(params[:id])

        render json: ProjectPresenter.new(project).as_json
      end
    end
  end
end
