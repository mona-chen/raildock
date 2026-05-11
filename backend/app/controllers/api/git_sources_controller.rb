module Api
  class GitSourcesController < BaseController
    def index
      if params[:organization_id]
        org = Organization.find(params[:organization_id])
        authorize_organization_access!(org)
        sources = org.git_sources
      else
        # Return personal git sources for the current user + global sources (backward compat)
        sources = GitSource.where(user_id: current_user.id)
                           .or(GitSource.where(user_id: nil, organization_id: nil))
      end
      render json: sources
    end

    def create
      source = GitSource.new(git_source_params.merge(connected: true))

      # Assign owner: organization if specified, otherwise current user
      if params[:organization_id]
        org = Organization.find(params[:organization_id])
        authorize_organization_access!(org)
        source.organization = org
      else
        source.user = current_user
      end

      if source.save
        render json: source, status: :created
      else
        render json: { errors: source.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      source = GitSource.find(params[:id])

      # Check access: org sources need org membership, personal sources need to be the owner
      if source.organization
        authorize_organization_access!(source.organization)
      elsif source.user && source.user != current_user
        return render json: { error: "Forbidden" }, status: :forbidden
      end

      source.update!(connected: false, access_token: nil)
      head :no_content
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    private

    def git_source_params
      params.permit(:provider, :access_token, :username, :installation_id, :auth_method, :account_type)
    end
  end
end
