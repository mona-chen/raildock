# Resolves what an agent credential may see.
#
# Shared by the v1 controllers and the MCP toolset so a token's project and
# environment binding is applied identically on both surfaces: an out-of-binding
# id is "not found", never a 403 that confirms it exists.
class AgentScope
  def initialize(organization:, token: nil)
    @organization = organization
    @token = token
  end

  def projects
    projects = Project.where(organization: organization)
    projects = projects.where(id: token.project_id) if token&.project_id
    projects
  end

  def services
    services = Service.where(project_id: projects.select(:id))
    services = services.where(environment_id: token.environment_id) if token&.environment_id
    services
  end

  def servers
    Server.where(organization_id: organization.id)
  end

  private

  attr_reader :organization, :token
end
