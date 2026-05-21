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
      # Personal projects - allow if user is authenticated
      # TODO: Add owner field to personal projects for proper authorization
      return true
    end

    membership = current_user.memberships.find_by(organization_id: project.organization_id)
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
      # Personal projects - allow if user is authenticated
      return true
    end

    membership = current_user.memberships.find_by(organization_id: project.organization_id)
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

    membership = current_user.memberships.find_by(organization_id: organization.id)
    unless membership
      render json: { error: "Forbidden" }, status: :forbidden and return
    end

    allowed_roles = PERMISSIONS.dig(:organization, action) || []
    unless allowed_roles.include?(membership.role.to_sym)
      render json: { error: "Forbidden" }, status: :forbidden and return
    end
  end

  def authorize_server!(action: :read)
    # Server authorization is based on organization role
    # Check current organization membership for server permissions
    return true unless current_organization

    membership = current_user.memberships.find_by(organization_id: current_organization.id)
    return true unless membership # Will be caught by authenticate_user!

    allowed_roles = PERMISSIONS.dig(:server, action) || []
    unless allowed_roles.include?(membership.role.to_sym)
      render json: { error: "Forbidden" }, status: :forbidden and return
    end
  end

  def scoped_projects
    if current_organization
      Project.where(organization: current_organization)
    else
      Project.where(organization_id: nil)
    end
  end

  # Get current user's role in the organization
  def current_role
    return nil unless current_organization

    membership = current_user.memberships.find_by(organization_id: current_organization.id)
    membership&.role&.to_sym
  end

  def admin_or_owner?
    %i[admin owner].include?(current_role)
  end

  def owner?
    current_role == :owner
  end
end