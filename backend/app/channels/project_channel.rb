class ProjectChannel < ApplicationCable::Channel
  def subscribed
    project = Project.find(params[:project_id])
    reject and return unless project_accessible?(project)

    stream_for project
  rescue ActiveRecord::RecordNotFound
    reject
  end

  private
    def project_accessible?(project)
      return false unless current_user
      return current_user.organizations.exists?(id: project.organization_id) if project.organization_id

      project.user_id == current_user.id || (project.user_id.nil? && current_user.admin?)
    end
end
