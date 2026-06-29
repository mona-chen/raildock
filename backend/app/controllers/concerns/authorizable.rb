module Authorizable
  extend ActiveSupport::Concern

  # Role-based permissions
  PERMISSIONS = {
    # Project permissions
    project: {
      read: %i[owner admin member],
      create: %i[owner admin],
      update: %i[owner admin],
      delete: %i[owner admin]
    },
    # Service permissions
    service: {
      read: %i[owner admin member],
      create: %i[owner admin],
      update: %i[owner admin],
      delete: %i[owner admin],
      # Operations
      deploy: %i[owner admin member],
      start: %i[owner admin member],
      stop: %i[owner admin member],
      restart: %i[owner admin member],
      scale: %i[owner admin member],
      logs: %i[owner admin member]
    },
    # Server permissions
    server: {
      read: %i[owner admin],
      create: %i[owner],
      update: %i[owner admin],
      delete: %i[owner]
    },
    # Organization permissions
    organization: {
      manage: %i[owner],
      settings: %i[owner admin],
      members: %i[owner admin]
    }
  }.freeze

  private

  def authorize_project!(project, action: :read)
    return true if project.nil?

    if project.organization_id.nil?
      return true if project.user_id == current_user.id
      return true if project.user_id.nil? && current_user.admin?

      render json: { error: "Forbidden" }, status: :forbidden and return
    end

    membership = current_user.organization_memberships.find_by(organization_id: project.organization_id)
    unless membership
      render json: { error: "Forbidden" }, status: :forbidden and return
    end

    allowed_roles = PERMISSIONS.dig(:project, action) || []
    unless allowed_roles.include?(membership.role.to_sym)
      render json: { error: "Forbidden" }, status: :forbidden and return
    end
  end

  def authorize_service!(service, action: :read)
    return true if service.nil?

    project = service.project
    return true if project.nil?

    if project.organization_id.nil?
      return true if project.user_id == current_user.id
      return true if project.user_id.nil? && current_user.admin?

      render json: { error: "Forbidden" }, status: :forbidden and return
    end

    membership = current_user.organization_memberships.find_by(organization_id: project.organization_id)
    unless membership
      render json: { error: "Forbidden" }, status: :forbidden and return
    end

    allowed_roles = PERMISSIONS.dig(:service, action) || PERMISSIONS.dig(:project, action) || []
    unless allowed_roles.include?(membership.role.to_sym)
      render json: { error: "Forbidden" }, status: :forbidden and return
    end
  end

  def authorize_organization!(organization, action: :settings)
    return true if organization.nil?

    membership = current_user.organization_memberships.find_by(organization_id: organization.id)
    unless membership
      render json: { error: "Forbidden" }, status: :forbidden and return
    end

    allowed_roles = PERMISSIONS.dig(:organization, action) || []
    unless allowed_roles.include?(membership.role.to_sym)
      render json: { error: "Forbidden" }, status: :forbidden and return
    end
  end

  def authorize_server!(action: :read)
    return true if current_user.admin?

    if current_organization
      membership = current_user.organization_memberships.find_by(organization_id: current_organization.id)
      unless membership
        render json: { error: "Forbidden" }, status: :forbidden and return
      end

      allowed_roles = PERMISSIONS.dig(:server, action) || []
      unless allowed_roles.include?(membership.role.to_sym)
        render json: { error: "Forbidden" }, status: :forbidden and return
      end
    else
      # Personal servers are only accessible by their owner; create requires an organization.
      render json: { error: "Forbidden" }, status: :forbidden and return if action == :create
    end
  end

  def scoped_projects
    if current_organization
      Project.where(organization: current_organization)
    else
      personal = Project.where(organization_id: nil, user_id: current_user.id)
      return personal unless current_user.admin?

      personal.or(Project.where(organization_id: nil, user_id: nil))
    end
  end

  def scoped_servers
    return Server.all if current_user.admin?

    if current_organization
      Server.where(organization: current_organization)
    else
      Server.where(organization_id: nil, user_id: current_user.id)
    end
  end

  # Get current user's role in the organization
  def current_role
    return nil unless current_organization

    membership = current_user.organization_memberships.find_by(organization_id: current_organization.id)
    membership&.role&.to_sym
  end

  def admin_or_owner?
    %i[admin owner].include?(current_role)
  end

  def owner?
    current_role == :owner
  end
end
