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
        redirect_to frontend_redirect_url(github_app: 'error', message: 'Missing installation_id')
        return
      end

      # Fetch actual installation details from GitHub (trust GitHub over frontend state)
      details = GithubAppService.installation_details(installation_id)
      account = details['account']

      unless account
        redirect_to frontend_redirect_url(github_app: 'error', message: 'Could not verify installation with GitHub')
        return
      end

      # Determine actual account type from GitHub
      account_type = account['type'] == 'Organization' ? 'organization' : 'personal'

      # Create or update a GitSource for this installation
      git_source = GitSource.find_or_initialize_by(
        provider: 'github',
        installation_id: installation_id.to_s
      )

      git_source.assign_attributes(
        auth_method: :oauth_app,
        connected: true,
        account_type: account_type,
        username: account['login']
      )

      # Associate with organization or user based on actual GitHub account type
      if account_type == 'organization'
        org = find_or_create_organization(account['login'], current_user)
        git_source.organization = org
        git_source.user = nil
      else
        git_source.user = current_user
        git_source.organization = nil
      end

      if git_source.save
        GithubSyncReposJob.perform_later(git_source.id)
        redirect_to frontend_redirect_url(github_app: 'success', git_source_id: git_source.id)
      else
        redirect_to frontend_redirect_url(github_app: 'error', message: git_source.errors.full_messages.join(', '))
      end
    rescue => e
      Rails.logger.error "GitHub App callback failed: #{e.message}"
      redirect_to frontend_redirect_url(github_app: 'error', message: 'Internal error')
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

    # POST /api/github-apps/finish-setup
    # Called by the frontend after GitHub redirects back from app installation
    def finish_setup
      installation_id = params[:installation_id]

      unless installation_id.present?
        render json: { error: 'Missing installation_id' }, status: :bad_request
        return
      end

      # Fetch installation details from GitHub
      details = GithubAppService.installation_details(installation_id)
      account = details['account']

      unless account
        render json: { error: 'Could not fetch installation details from GitHub' }, status: :bad_gateway
        return
      end

      # Determine account type from GitHub's response
      account_type = account['type'] == 'Organization' ? 'organization' : 'personal'

      # Create or update the GitSource
      git_source = GitSource.find_or_initialize_by(
        provider: 'github',
        installation_id: installation_id.to_s
      )

      git_source.assign_attributes(
        auth_method: :oauth_app,
        connected: true,
        account_type: account_type,
        username: account['login']
      )

      # Associate with organization or user based on actual GitHub account type
      if account_type == 'organization'
        org = find_or_create_organization(account['login'], current_user)
        git_source.organization = org
        git_source.user = nil
      else
        git_source.user = current_user
        git_source.organization = nil
      end

      if git_source.save
        GithubSyncReposJob.perform_later(git_source.id)
        render json: {
          success: true,
          git_source: git_source.as_json,
          message: "GitHub App installed successfully for #{account['login']}"
        }
      else
        render json: { error: git_source.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error "GitHub App finish_setup failed: #{e.message}"
      render json: { error: 'Failed to complete GitHub App setup' }, status: :internal_server_error
    end

    private

    def find_or_create_organization(name, owner)
      slug = name.parameterize
      org = Organization.find_by(slug: slug)
      return org if org

      Organization.create!(
        name: name,
        slug: slug,
        owner: owner
      )
    rescue ActiveRecord::RecordInvalid
      # Fallback: try to find by name if slug collision
      Organization.find_by(name: name) || Organization.create!(name: name, slug: "#{slug}-#{SecureRandom.hex(4)}", owner: owner)
    end

    def decode_state(state)
      return {} unless state.present?
      JSON.parse(Base64.urlsafe_decode64(state))
    rescue
      {}
    end

    def frontend_redirect_url(params = {})
      base = ENV.fetch('FRONTEND_URL') { request.base_url }
      query = URI.encode_www_form(params)
      "#{base}/#/dashboard/settings?tab=git-sources&#{query}"
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

      if git_source.nil? && %w[created new_permissions_accepted].include?(action)
        # Create a GitSource from webhook if it doesn't exist (fallback)
        account = installation['account']
        account_type = account['type'] == 'Organization' ? 'organization' : 'personal'

        git_source = GitSource.new(
          provider: 'github',
          installation_id: installation['id'].to_s,
          auth_method: :oauth_app,
          connected: true,
          account_type: account_type,
          username: account['login']
        )

        if account_type == 'organization'
          # Webhook can't determine owner — create org without owner for now
          org = Organization.find_by(slug: account['login'].parameterize)
          org ||= Organization.create!(name: account['login'], slug: account['login'].parameterize, owner: User.first)
          git_source.organization = org
        else
          git_source.user = User.first
        end

        git_source.save!
        GithubSyncReposJob.perform_later(git_source.id)
        return
      end

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
