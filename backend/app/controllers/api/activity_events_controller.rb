module Api
  class ActivityEventsController < BaseController
    include Authorizable

    def index
      project = scoped_projects.find(params[:project_id])
      events = ActivityEvent.where(project_id: project.id).limit(50)
      render json: events
    end

    def global
      events = ActivityEvent.where(project_id: scoped_projects.select(:id)).limit(100)
      render json: events
    end
  end
end
