module Api
  class GithubAppsController < BaseController
    skip_before_action :authenticate_user!, only: [:callback, :webhook]

    # GET /api/github-apps/callback
    # GitHub redirects here after a user installs the app or accepts the OAuth flow
    def callback
      installation_id = params[:installation_id]
      setup_action = params[:setup_action]
      state = params[:state]

      unless installation_id.present?
        render json: { error: "Missing installation_id" }, status: :bad_request
        return
      end

      # Decode state param to get the organization/user context
      context = decode_state(state)

      # Create or update a GitSource for this installation
      git_source = GitSource.find_or_initialize_by(
        provider: 'github',
        installation_id: installation_id
      )

      git_source.assign_attributes(
        auth_method: :oauth_app,
        connected: true,
        account_type: context['account_type'] || 'personal'
      )

      if context['organization_id'].present?
        git_source.organization_id = context['organization_id']
        git_source.user = nil
      else
        git_source.user_id = context['user_id']
        git_source.organization = nil
      end

      if git_source.save
        # Fetch repos asynchronously
        GithubSyncReposJob.perform_later(git_source.id)
        render json: { success: true, git_source_id: git_source.id }
      else
        render json: { errors: git_source.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # POST /api/github-apps/webhook
    # Receives GitHub App events (push, pull_request, installation, etc.)
    def webhook
      payload = request.body.read
      signature = request.headers['X-Hub-Signature-256']

      unless verify_webhook(payload, signature)
        render json: { error: "Invalid signature" }, status: :forbidden
        return
      end

      event = request.headers['X-GitHub-Event']
      data = JSON.parse(payload)

      case event
      when 'installation'
        handle_installation_event(data)
      when 'push'
        handle_push_event(data)
      when 'pull_request'
        handle_pull_request_event(data)
      end

      head :no_content
    rescue JSON::ParserError
      render json: { error: "Invalid JSON" }, status: :bad_request
    end

    private

    def decode_state(state)
      return {} unless state.present?
      JSON.parse(Base64.urlsafe_decode64(state))
    rescue
      {}
    end

    def verify_webhook(payload, signature)
      secret = GithubAppService.webhook_secret
      return true if secret.blank? # Allow unverified in dev if no secret configured

      expected = 'sha256=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), secret, payload)
      ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
    end

    def handle_installation_event(data)
      action = data['action']
      installation = data['installation']
      return unless installation

      git_source = GitSource.find_by(installation_id: installation['id'].to_s, provider: 'github')
      return unless git_source

      case action
      when 'deleted'
        git_source.update!(connected: false)
      when 'created', 'new_permissions_accepted'
        git_source.update!(connected: true)
        GithubSyncReposJob.perform_later(git_source.id)
      end
    end

    def handle_push_event(data)
      repo_full_name = data.dig('repository', 'full_name')
      branch = data['ref']&.sub('refs/heads/', '')
      return unless repo_full_name && branch

      # Find services linked to this repo/branch and trigger deploy
      Service.where(git_repo: repo_full_name).find_each do |service|
        next unless service.branch == branch
        deployment = service.deployments.create!(
          status: :pending,
          branch: branch,
          commit_sha: data.dig('after')&.first(7)
        )
        DeploymentJob.perform_later(service.id, deployment.id)
        service.update!(status: :deploying)
      end
    end

    def handle_pull_request_event(data)
      # Future: preview deployments for PRs
    end
  end
end
