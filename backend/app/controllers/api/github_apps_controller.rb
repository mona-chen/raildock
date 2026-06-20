require "digest"

module Api
  class GithubAppsController < BaseController
    skip_before_action :authenticate_user!, only: [ :callback, :webhook ]

    # GET /api/github-apps/callback
    # GitHub redirects here after the user authorizes RailDock to verify the
    # installation selected during setup.
    def callback
      code = params[:code]
      state = params[:state]
      setup = decode_setup_state(state)
      callback_user = User.find_by(id: setup["user_id"])
      installation_id = setup["installation_id"].to_s

      unless code.present? && installation_id.present?
        redirect_to frontend_redirect_url(github_app: "error", message: "Missing GitHub authorization details"), allow_other_host: true
        return
      end

      unless callback_user
        redirect_to frontend_redirect_url(github_app: "error", message: "Invalid setup state"), allow_other_host: true
        return
      end

      user_token = GithubAppService.exchange_user_code(code, callback_url: github_callback_url)
      installation = GithubAppService.user_installations(user_token).find do |candidate|
        candidate["id"].to_s == installation_id
      end
      account = installation&.dig("account")

      unless account
        redirect_to frontend_redirect_url(github_app: "error", message: "GitHub installation is not accessible to this user"), allow_other_host: true
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

      assign_raildock_owner(git_source, callback_user, setup["organization_id"], redirect: true)
      return if performed?

      if git_source.save
        GithubSyncReposJob.perform_later(git_source.id)
        redirect_to frontend_redirect_url(github_app: "success", git_source_id: git_source.id), allow_other_host: true
      else
        redirect_to frontend_redirect_url(github_app: "error", message: git_source.errors.full_messages.join(", ")), allow_other_host: true
      end
    rescue => e
      Rails.logger.error "GitHub App callback failed: #{e.message}"
      redirect_to frontend_redirect_url(github_app: "error", message: "Failed to verify GitHub installation"), allow_other_host: true
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
    # Starts GitHub's user authorization flow so the installation ID received
    # by the setup URL can be verified against the installing GitHub user.
    def finish_setup
      installation_id = params[:installation_id]

      unless installation_id.present?
        render json: { error: "Missing installation_id" }, status: :bad_request
        return
      end

      authorize_raildock_organization(params[:organization_id])
      return if performed?

      state = encode_setup_state(
        user_id: current_user.id,
        organization_id: params[:organization_id],
        installation_id: installation_id.to_s
      )
      render json: {
        authorization_url: GithubAppService.user_authorization_url(
          state,
          callback_url: github_callback_url
        )
      }
    rescue => e
      Rails.logger.error "GitHub App finish_setup failed: #{e.message}"
      render json: { error: "Failed to complete GitHub App setup" }, status: :internal_server_error
    end

    private

    def assign_raildock_owner(git_source, user, organization_id, redirect: false)
      if organization_id.present?
        organization = Organization.find_by(id: organization_id)
        unless organization && user.organizations.exists?(organization.id)
          if redirect
            redirect_to frontend_redirect_url(github_app: "error", message: "Forbidden"), allow_other_host: true
          else
            render json: { error: "Forbidden" }, status: :forbidden
          end
          return
        end

        git_source.organization = organization
        git_source.user = nil
      else
        git_source.user = user
        git_source.organization = nil
      end
    end

    def authorize_raildock_organization(organization_id)
      return if organization_id.blank?

      organization = Organization.find_by(id: organization_id)
      render json: { error: "Forbidden" }, status: :forbidden unless organization && current_user.organizations.exists?(organization.id)
    end

    def encode_setup_state(payload)
      JWT.encode(payload.merge(exp: 15.minutes.from_now.to_i), Rails.application.secret_key_base, "HS256")
    end

    def decode_setup_state(state)
      JWT.decode(state.to_s, Rails.application.secret_key_base, true, algorithm: "HS256").first
    rescue JWT::DecodeError, JWT::ExpiredSignature
      {}
    end

    def frontend_redirect_url(params = {})
      query = URI.encode_www_form(params)
      "#{public_base_url}/#/dashboard/settings?tab=git-sources&#{query}"
    end

    def github_callback_url
      "#{public_base_url}/api/github-apps/callback"
    end

    def public_base_url
      configured_url =
        ENV["RAILDOCK_PUBLIC_URL"].presence ||
        ENV["APP_URL"].presence ||
        public_frontend_url

      (configured_url.presence || request.base_url).delete_suffix("/")
    end

    def public_frontend_url
      frontend_url = ENV["FRONTEND_URL"].presence
      return if frontend_url.blank?

      uri = URI.parse(frontend_url)
      return if uri.host.in?(%w[localhost 127.0.0.1 ::1])

      frontend_url
    rescue URI::InvalidURIError
      nil
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
      trigger_deployments_for_push(
        data,
        git_source: git_source,
        triggered_by: "github_app",
        delivery_id: request.headers["X-GitHub-Delivery"]
      )
    end

    def handle_pull_request_event(data)
      # Future: preview deployments for PRs
    end

    def trigger_deployments_for_push(data, git_source:, triggered_by:, delivery_id: nil)
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

        identity = delivery_id.presence || [ repo["full_name"], branch, commit_sha ].join(":")
        deployment, created = Deployment.create_idempotently!(
          service: service,
          key: Digest::SHA256.hexdigest("github-app:#{service.id}:#{identity}"),
          attributes: {
            status: :pending,
            started_at: Time.current,
            branch: branch,
            commit_sha: commit_sha,
            commit_message: data.dig("head_commit", "message").to_s.lines.first&.strip,
            triggered_by: triggered_by
          }
        )
        next unless created

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
