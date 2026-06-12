module Api
  class GithubAppsController < BaseController
    skip_before_action :authenticate_user!, only: [ :callback, :webhook ]

    # GET /api/github-apps/callback
    # GitHub redirects here after a user installs the app or accepts the OAuth flow
    def callback
      installation_id = params[:installation_id]
      setup_action = params[:setup_action]
      state = params[:state]
      callback_user = user_from_state(state)

      unless installation_id.present?
        redirect_to frontend_redirect_url(github_app: "error", message: "Missing installation_id")
        return
      end

      unless callback_user
        redirect_to frontend_redirect_url(github_app: "error", message: "Invalid setup state")
        return
      end

      # Fetch actual installation details from GitHub (trust GitHub over frontend state)
      details = GithubAppService.installation_details(installation_id)
      account = details["account"]

      unless account
        redirect_to frontend_redirect_url(github_app: "error", message: "Could not verify installation with GitHub")
        return
      end

      # Determine actual account type from GitHub
      account_type = account["type"] == "Organization" ? "organization" : "personal"

      # Create or update a GitSource for this installation
      git_source = GitSource.find_or_initialize_by(
        provider: "github",
        installation_id: installation_id.to_s
      )

      git_source.assign_attributes(
        auth_method: :oauth_app,
        connected: true,
        account_type: account_type,
        username: account["login"]
      )

      # Associate with organization or user based on actual GitHub account type
      if account_type == "organization"
        org = find_or_create_organization(account["login"], callback_user)
        git_source.organization = org
        git_source.user = nil
      else
        git_source.user = callback_user
        git_source.organization = nil
      end

      if git_source.save
        GithubSyncReposJob.perform_later(git_source.id)
        redirect_to frontend_redirect_url(github_app: "success", git_source_id: git_source.id)
      else
        redirect_to frontend_redirect_url(github_app: "error", message: git_source.errors.full_messages.join(", "))
      end
    rescue => e
      Rails.logger.error "GitHub App callback failed: #{e.message}"
      redirect_to frontend_redirect_url(github_app: "error", message: "Internal error")
    end

    # DELETE /api/github-apps/installations/:id
    # Uninstalls a GitHub App from the account and removes the GitSource
    def destroy_installation
      installation_id = params[:id]

      unless installation_id.present?
        render json: { error: "Missing installation_id" }, status: :bad_request
        return
      end

      git_source = GitSource.find_by(installation_id: installation_id.to_s, provider: "github")

      unless git_source
        render json: { error: "Installation not found" }, status: :not_found
        return
      end

      # Verify ownership
      if git_source.organization
        authorize_organization_access!(git_source.organization)
      elsif git_source.user && git_source.user != current_user
        return render json: { error: "Forbidden" }, status: :forbidden
      end

      # Delete from GitHub (404 = already uninstalled, which is fine)
      begin
        GithubAppService.delete_installation(installation_id)
      rescue => e
        if e.message.include?("404")
          Rails.logger.info "GitHub App installation #{installation_id} already removed from GitHub"
        else
          raise
        end
      end

      # Clean up our database
      git_source.destroy!

      render json: { success: true, message: "GitHub App uninstalled successfully" }
    rescue => e
      Rails.logger.error "GitHub App destroy_installation failed: #{e.message}"
      render json: { error: "Failed to uninstall GitHub App" }, status: :internal_server_error
    end

    # POST /api/github-apps/webhook
    # Receives GitHub App events (push, pull_request, installation, etc.)
    def webhook
      payload = request.body.read
      signature = request.headers["X-Hub-Signature-256"]

      unless verify_webhook(payload, signature)
        render json: { error: "Invalid signature" }, status: :forbidden
        return
      end

      event = request.headers["X-GitHub-Event"]
      data = JSON.parse(payload)

      case event
      when "installation"
        handle_installation_event(data)
      when "installation_repositories"
        handle_installation_repositories_event(data)
      when "push"
        handle_push_event(data)
      when "pull_request"
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
        render json: { error: "Missing installation_id" }, status: :bad_request
        return
      end

      # Fetch installation details from GitHub
      details = GithubAppService.installation_details(installation_id)
      account = details["account"]

      unless account
        render json: { error: "Could not fetch installation details from GitHub" }, status: :bad_gateway
        return
      end

      # Determine account type from GitHub's response
      account_type = account["type"] == "Organization" ? "organization" : "personal"

      # Create or update the GitSource
      git_source = GitSource.find_or_initialize_by(
        provider: "github",
        installation_id: installation_id.to_s
      )

      git_source.assign_attributes(
        auth_method: :oauth_app,
        connected: true,
        account_type: account_type,
        username: account["login"]
      )

      # Associate with organization or user based on actual GitHub account type
      if account_type == "organization"
        org = find_or_create_organization(account["login"], current_user)
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
        render json: { error: git_source.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error "GitHub App finish_setup failed: #{e.message}"
      render json: { error: "Failed to complete GitHub App setup" }, status: :internal_server_error
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

    def user_from_state(state)
      decoded = decode_state(state)
      User.find_by(id: decoded["user_id"] || decoded[:user_id])
    end

    def frontend_redirect_url(params = {})
      base = ENV.fetch("FRONTEND_URL") { request.base_url }
      query = URI.encode_www_form(params)
      "#{base}/#/dashboard/settings?tab=git-sources&#{query}"
    end

    def verify_webhook(payload, signature)
      secret = GithubAppService.webhook_secret
      return !Rails.env.production? if secret.blank?

      expected = "sha256=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, payload)
      ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
    end

    def handle_installation_event(data)
      action = data["action"]
      installation = data["installation"]
      return unless installation

      git_source = GitSource.find_by(installation_id: installation["id"].to_s, provider: "github")

      if git_source.nil?
        Rails.logger.info "Ignoring GitHub installation #{installation['id']} #{action} webhook until a user completes setup"
        return
      end

      case action
      when "deleted"
        git_source.update!(connected: false)
      when "created", "new_permissions_accepted"
        git_source.update!(connected: true)
        GithubSyncReposJob.perform_later(git_source.id)
      end
    end

    def handle_installation_repositories_event(data)
      installation_id = data.dig("installation", "id")
      return unless installation_id

      git_source = GitSource.find_by(installation_id: installation_id.to_s, provider: "github")
      return unless git_source

      GithubSyncReposJob.perform_later(git_source.id)
    end

    def handle_push_event(data)
      installation_id = data.dig("installation", "id")
      git_source = GitSource.find_by(installation_id: installation_id.to_s, provider: "github") if installation_id
      trigger_deployments_for_push(data, git_source: git_source, triggered_by: "github_app")
    end

    def handle_pull_request_event(data)
      # Future: preview deployments for PRs
    end

    def trigger_deployments_for_push(data, git_source:, triggered_by:)
      repo = data["repository"] || {}
      branch = data["ref"].to_s.delete_prefix("refs/heads/")
      commit_sha = data["after"].to_s
      return if repo.blank? || branch.blank?
      return if commit_sha.blank? || commit_sha.match?(/\A0+\z/)

      identifiers = [
        repo["full_name"],
        repo["clone_url"],
        repo["ssh_url"],
        repo["html_url"],
        repo["url"]
      ]

      services = Service.matching_repo(*identifiers).where(auto_deploy: true).includes(project: :organization)
      services = services.select { |service| github_source_can_deploy_service?(git_source, service) } if git_source

      services.each do |service|
        next unless auto_deploy_branch_matches?(service, branch, repo["default_branch"])

        deployment = service.deployments.create!(
          status: :pending,
          started_at: Time.current,
          branch: branch,
          commit_sha: commit_sha,
          triggered_by: triggered_by
        )
        DeploymentJob.perform_later(service.id, deployment.id)
        service.update!(status: :deploying)
      end
    end

    def auto_deploy_branch_matches?(service, branch, default_branch)
      expected = service.branch.presence || default_branch.presence || branch
      ActiveSupport::SecurityUtils.secure_compare(expected, branch)
    rescue ArgumentError
      false
    end

    def github_source_can_deploy_service?(git_source, service)
      return false unless git_source&.connected?

      project = service.project
      if git_source.organization_id.present?
        project.organization_id == git_source.organization_id
      else
        project.organization_id.nil? && project.user_id == git_source.user_id
      end
    end
  end
end
