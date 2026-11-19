module Api
  module V1
    # One call to orient an agent: what exists, how it is wired, and what this
    # credential is allowed to do. Secrets never appear here.
    class ContextPresenter
      def initialize(organization:, projects:, servers:, role:, token: nil, user:)
        @organization = organization
        @projects = projects
        @servers = servers
        @role = role
        @token = token
        @user = user
      end

      def as_json
        {
          organization: {
            id: organization.id.to_s,
            name: organization.name,
            slug: organization.slug
          },
          actor: {
            type: token ? "api_token" : "user",
            id: (token&.id || user.id).to_s,
            role: role&.to_s,
            scopes: token&.scopes,
            project_id: token&.project_id&.to_s,
            environment_id: token&.environment_id&.to_s,
            expires_at: token&.expires_at&.iso8601
          },
          capabilities: capabilities,
          counts: {
            servers: servers.size,
            projects: projects.size,
            services: projects.sum { |project| project.services.size }
          },
          servers: servers.map do |server|
            {
              id: server.id.to_s,
              name: server.name,
              host: server.public_ip.presence || server.host,
              status: server.status,
              os: server.os
            }
          end,
          projects: projects.map { |project| ProjectPresenter.new(project).as_json }
        }
      end

      private

      attr_reader :organization, :projects, :servers, :role, :token, :user

      def capabilities
        scopes = token ? token.scopes : ApiToken::SCOPES
        role = self.role&.to_sym

        {
          read: true,
          deploy: scopes.include?("deploy") && %i[owner admin member].include?(role),
          config_write: scopes.include?("config:write") && %i[owner admin].include?(role),
          destructive: scopes.include?("destructive") && %i[owner admin].include?(role)
        }
      end
    end
  end
end
