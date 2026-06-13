require "digest"

module Api
  class WebhooksController < ActionController::API
    # Skip auth for webhooks — they use token-based verification
    skip_before_action :authenticate_user!, raise: false

    before_action :verify_webhook_signature!, only: [ :deploy ]

    def deploy
      # Extract repo info from webhook payload (GitHub/GitLab format)
      repository = params[:repository] || {}
      project = params[:project] || {}
      repo_name = repository[:full_name] || repository["full_name"] || project[:path_with_namespace] || project["path_with_namespace"]
      ref = params[:ref].to_s
      branch = ref.delete_prefix("refs/heads/").presence || params[:branch].presence || "main"

      return head :bad_request unless repo_name

      # Find services linked to this repo that have auto_deploy enabled
      services = Service.matching_repo(
        repo_name,
        repository[:clone_url] || repository["clone_url"],
        repository[:ssh_url] || repository["ssh_url"],
        repository[:html_url] || repository["html_url"],
        project[:git_http_url] || project["git_http_url"],
        project[:git_ssh_url] || project["git_ssh_url"],
      ).where(auto_deploy: true)

      services = services.select do |service|
        expected_branch = service.branch.presence ||
          repository[:default_branch] || repository["default_branch"] ||
          project[:default_branch] || project["default_branch"] ||
          "main"
        expected_branch == branch
      end

      return head :not_found if services.empty?

      services.each do |service|
        commit_sha = params[:after].presence || params[:checkout_sha].presence
        deployment, created = Deployment.create_idempotently!(
          service: service,
          key: webhook_idempotency_key(service, repo_name, branch, commit_sha),
          attributes: {
            status: :pending,
            started_at: Time.current,
            branch: branch,
            commit_sha: commit_sha,
            triggered_by: "webhook"
          }
        )
        next unless created

        DeploymentJob.perform_later(service.id, deployment.id)
        service.update!(status: :deploying)
      end

      head :accepted
    end

    def service_deploy
      service = Service.find_by(id: params[:id], webhook_token: params[:token])
      return head :not_found unless service
      return render json: { error: "Database services cannot be deployed" }, status: :unprocessable_entity if service.service_type_database?

      branch = params[:branch] || service.branch || "main"

      deployment = service.deployments.create!(
        status: :pending,
        started_at: Time.current,
        branch: branch,
        triggered_by: "webhook"
      )
      DeploymentJob.perform_later(service.id, deployment.id)
      service.update!(status: :deploying)

      render json: { deployment_id: deployment.id, status: :deploying }, status: :accepted
    end

    private

    def verify_webhook_signature!
      secret = webhook_secret
      if secret.blank?
        return unless Rails.env.production?

        render json: { error: "Webhook secret is not configured" }, status: :forbidden
        return
      end

      payload = request.body.read
      request.body.rewind

      # GitHub: X-Hub-Signature-256
      github_sig = request.headers["X-Hub-Signature-256"]
      if github_sig.present?
        expected = "sha256=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, payload)
        unless ActiveSupport::SecurityUtils.secure_compare(expected, github_sig)
          render json: { error: "Invalid signature" }, status: :forbidden
          return
        end
        return
      end

      # GitLab: X-Gitlab-Token
      gitlab_token = request.headers["X-Gitlab-Token"]
      if gitlab_token.present?
        unless ActiveSupport::SecurityUtils.secure_compare(secret, gitlab_token)
          render json: { error: "Invalid token" }, status: :forbidden
          return
        end
        return
      end

      # Generic: X-Webhook-Secret or token query param
      generic_token = request.headers["X-Webhook-Secret"] || params[:token]
      if generic_token.present?
        unless ActiveSupport::SecurityUtils.secure_compare(secret, generic_token)
          render json: { error: "Invalid token" }, status: :forbidden
          return
        end
        return
      end

      # If a secret is configured but no auth header was provided, reject
      render json: { error: "Missing authentication" }, status: :forbidden
    end

    def webhook_secret
      ENV["WEBHOOK_SECRET"].presence || Rails.application.credentials.dig(:webhook_secret)
    end

    def webhook_idempotency_key(service, repo_name, branch, commit_sha)
      delivery_id = request.headers["X-GitHub-Delivery"].presence ||
        request.headers["X-Gitlab-Event-UUID"].presence
      identity = delivery_id || [ repo_name, branch, commit_sha.presence || "unknown" ].join(":")

      Digest::SHA256.hexdigest("generic-webhook:#{service.id}:#{identity}")
    end
  end
end
