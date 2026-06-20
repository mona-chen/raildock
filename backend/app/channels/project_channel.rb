class ProjectChannel < ApplicationCable::Channel
  def subscribed
    project = Project.find(params[:project_id])
    reject and return unless project_accessible?(project)

    stream_for project
  rescue ActiveRecord::RecordNotFound
    reject
  end
end
