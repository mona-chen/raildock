module Api
  class GitSourcesController < BaseController
    def index
      if params[:organization_id]
        org = Organization.find(params[:organization_id])
        authorize_organization_access!(org)
        sources = org.git_sources
      else
        # Personal context: user's own sources + any org sources they belong to
        user_org_ids = current_user.organization_memberships.pluck(:organization_id)
        sources = GitSource.where(user_id: current_user.id)
                           .or(GitSource.where(organization_id: user_org_ids))
      end
      render json: sources
    end

    def create
      source = GitSource.new(git_source_params.merge(connected: true, auth_method: :token))

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
      source = find_source

      metadata = source.metadata || {}
      has_repos = source.repos.present?
      sync_error = metadata["sync_error"]
      sync_failed_at = metadata["sync_failed_at"]
      recently_failed = sync_failed_at.present? && Time.parse(sync_failed_at) > 5.minutes.ago rescue false

      # Trigger async refresh only if we don't have repos AND haven't recently failed
      if source.github_app? && !has_repos && !recently_failed
        GithubSyncReposJob.perform_later(source.id) rescue nil
      end

      render json: {
        repos: source.repos,
        syncing: source.github_app? && !has_repos && !recently_failed,
        error: recently_failed ? sync_error : nil
      }
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    def branches
      source = find_source
      return render json: { error: "Git source is not a GitHub App" }, status: :unprocessable_entity unless source.github_app?

      repo = Service.repo_full_name(params.require(:repository))
      return render json: { error: "Repository not accessible" }, status: :forbidden unless repository_allowed?(source, repo)

      client = GithubAppService.installation_client(source.installation_id)
      client.auto_paginate = true
      names = client.branches(repo).map(&:name)
      render json: { branches: names }
    rescue Octokit::NotFound => e
      render json: { error: e.message }, status: :not_found
    rescue Octokit::Error => e
      render json: { error: e.message }, status: :bad_gateway
    end

    def directories
      source = find_source
      return render json: { error: "Git source is not a GitHub App" }, status: :unprocessable_entity unless source.github_app?

      repo = Service.repo_full_name(params.require(:repository))
      return render json: { error: "Repository not accessible" }, status: :forbidden unless repository_allowed?(source, repo)

      branch = params[:branch].presence || "main"
      client = GithubAppService.installation_client(source.installation_id)
      sha = client.branch(repo, branch).commit.sha
      tree = client.tree(repo, sha, recursive: true)

      dirs = tree.tree.filter_map { |entry| entry.type == "tree" ? entry.path : nil }.sort
      dirs.unshift(".") unless dirs.include?(".")
      render json: { directories: dirs }
    rescue Octokit::NotFound => e
      render json: { error: e.message }, status: :not_found
    rescue Octokit::Error => e
      render json: { error: e.message }, status: :bad_gateway
    end

    private

    def find_source
      source = GitSource.find(params[:id])

      if source.organization
        authorize_organization_access!(source.organization)
      elsif source.user && source.user != current_user
        raise ActiveRecord::RecordNotFound
      end

      source
    end

    def repository_allowed?(source, repo)
      source.repos.any? do |r|
        Service.repo_full_name(r["full_name"] || r[:full_name] || r["clone_url"] || r[:clone_url]) == repo
      end
    end

    def git_source_params
      params.permit(:provider, :access_token, :username)
    end
  end
end
