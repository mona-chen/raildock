module Api
  class WebhooksController < ActionController::API
    # Skip auth for webhooks — they use token-based verification
    skip_before_action :authenticate_user!, raise: false

    def deploy
      # Extract repo info from webhook payload (GitHub/GitLab format)
      repo_name = params[:repository]&.[]('full_name') || params[:project]&.[]('path_with_namespace')
      ref = params[:ref] || ''
      branch = ref.split('/').last || 'main'

      return head :bad_request unless repo_name

      # Find services linked to this repo
      services = Service.where(git_repo: repo_name)
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
  end
end
