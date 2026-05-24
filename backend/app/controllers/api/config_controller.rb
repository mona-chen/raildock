module Api
  class ConfigController < BaseController
    # GET /api/config
    # Returns public configuration safe to expose to the frontend
    def index
      render json: {
        github_app: {
          enabled: GithubAppService.enabled?,
          app_slug: GithubAppService.app_slug,
          client_id: GithubAppService.client_id,
        }
      }
    end
  end
end
