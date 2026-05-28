module Api
  class WebhooksController < ActionController::API
    # Skip auth for webhooks — they use token-based verification
    skip_before_action :authenticate_user!, raise: false

    before_action :verify_webhook_signature!, only: [:deploy]

    def deploy
      # Extract repo info from webhook payload (GitHub/GitLab format)
      repo_name = params[:repository]&.[]('full_name') || params[:project]&.[]('path_with_namespace')
      ref = params[:ref] || ''
      branch = ref.split('/').last || 'main'

      return head :bad_request unless repo_name

      # Find services linked to this repo that have auto_deploy enabled
      services = Service.where(git_repo: repo_name, auto_deploy: true)
      return head :not_found if services.empty?

      services.each do |service|
        deployment = service.deployments.create!(
          status: :pending,
          started_at: Time.current,
          branch: branch
        )
        DeploymentJob.perform_later(service.id, deployment.id)
        service.update!(status: :deploying)
      end

      head :accepted
    end

    def service_deploy
      service = Service.find_by(id: params[:id], webhook_token: params[:token])
      return head :not_found unless service

      branch = params[:branch] || service.branch || 'main'

      deployment = service.deployments.create!(
        status: :pending,
        started_at: Time.current,
        branch: branch,
        triggered_by: 'webhook'
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
      github_sig = request.headers['X-Hub-Signature-256']
      if github_sig.present?
        expected = 'sha256=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), secret, payload)
        unless ActiveSupport::SecurityUtils.secure_compare(expected, github_sig)
          render json: { error: "Invalid signature" }, status: :forbidden
          return
        end
        return
      end

      # GitLab: X-Gitlab-Token
      gitlab_token = request.headers['X-Gitlab-Token']
      if gitlab_token.present?
        unless ActiveSupport::SecurityUtils.secure_compare(secret, gitlab_token)
          render json: { error: "Invalid token" }, status: :forbidden
          return
        end
        return
      end

      # Generic: X-Webhook-Secret or token query param
      generic_token = request.headers['X-Webhook-Secret'] || params[:token]
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
  end
end
