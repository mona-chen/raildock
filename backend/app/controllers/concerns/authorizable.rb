module Authorizable
  extend ActiveSupport::Concern

  private

  def authorize_project!(project)
    return true if project.nil?

    # Personal projects (no org) — allow any authenticated user for now
    # until a proper owner field is added
    if project.organization_id.nil?
      return true
    end

    unless current_user.organizations.exists?(id: project.organization_id)
      render json: { error: "Forbidden" }, status: :forbidden
    end
  end

  def authorize_service!(service)
    authorize_project!(service&.project)
  end

  def scoped_projects
    if current_organization
      Project.where(organization: current_organization)
    else
      Project.where(organization_id: nil)
    end
  end
end
