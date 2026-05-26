module Api
  class GitSourcesController < BaseController
    def index
      if params[:organization_id]
        org = Organization.find(params[:organization_id])
        authorize_organization_access!(org)
        # Show org sources + personal GitHub App sources the user has access to
        # (GitHub App installations for personal accounts should still be visible in org context)
        sources = org.git_sources.or(
          GitSource.where(user_id: current_user.id, organization_id: nil)
        ).where(auth_method: 'oauth_app').or(
          GitSource.where(organization_id: org.id)
        )
        # Simplify: show all GitHub App sources accessible to this user in this org context
        sources = GitSource.where(
          "organization_id = ? OR (organization_id IS NULL AND user_id = ? AND auth_method = 'oauth_app')",
          org.id, current_user.id
        )
      else
        # Personal context: user's own sources + any org sources they belong to
        user_org_ids = current_user.organization_memberships.pluck(:organization_id)
        sources = GitSource.where(user_id: current_user.id)
                           .or(GitSource.where(organization_id: user_org_ids))
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

    def repos
      source = GitSource.find(params[:id])

      if source.organization
        authorize_organization_access!(source.organization)
      elsif source.user && source.user != current_user
        return render json: { error: "Forbidden" }, status: :forbidden
      end

      metadata = source.metadata || {}
      has_repos = source.repos.present?
      sync_error = metadata['sync_error']
      sync_failed_at = metadata['sync_failed_at']
      recently_failed = sync_failed_at.present? && Time.parse(sync_failed_at) > 5.minutes.ago rescue false

      # Trigger async refresh only if we don't have repos AND haven't recently failed
      if !has_repos && !recently_failed
        GithubSyncReposJob.perform_later(source.id) rescue nil
      end

      render json: {
        repos: source.repos,
        syncing: !has_repos && !recently_failed,
        error: recently_failed ? sync_error : nil
      }
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    private

    def git_source_params
      params.permit(:provider, :access_token, :username, :installation_id, :auth_method, :account_type)
    end
  end
end
