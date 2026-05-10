module Api
  class ActivityEventsController < BaseController
    def index
      events = ActivityEvent.where(project_id: params[:project_id]).limit(50)
      render json: events
    end

    def global
      events = ActivityEvent.limit(100)
      render json: events
    end
  end
end
