module Api
  module V1
    class ServicesController < BaseController
      before_action :require_read_scope, only: [ :show, :logs, :diagnose ]

      def show
        render json: ServicePresenter.new(service).as_json
      end

      def logs
        limit = params[:lines].present? ? params[:lines].to_i.clamp(1, 500) : 100

        render json: AgentLogs.new(service: service, limit: limit).payload
      end

      def diagnose
        render json: DiagnosisPresenter.new(service).as_json
      end

      def deploy
        return unless require_scope!(:deploy)

        target = service
        authorize_service!(target, action: :deploy)

        if target.service_type == "database"
          return render json: {
            error: "Database services cannot be deployed. They are managed directly by Dokku.",
            code: "not_deployable"
          }, status: :unprocessable_entity
        end

        key = idempotency_key!
        return unless key

        result = writes.deploy(
          service: target,
          key: key,
          branch: params[:branch],
          commit_sha: params[:commit_sha],
          commit_message: params[:commit_message]
        )

        render_operation(result.operation, status: result.created ? :accepted : :ok)
      rescue AgentWrites::IdempotencyConflict
        render_idempotency_conflict
      end

      def restart
        return unless require_scope!(:deploy)

        target = service
        authorize_service!(target, action: :restart)

        if target.project&.server&.ssh_key.blank?
          return render json: {
            error: "No server SSH key configured for this service",
            code: "server_unavailable"
          }, status: :unprocessable_entity
        end

        key = idempotency_key!
        return unless key

        result = writes.restart(service: target, key: key)

        render_operation(result.operation, status: result.created ? :accepted : :ok)
      rescue AgentWrites::IdempotencyConflict
        render_idempotency_conflict
      end

      def rollback
        return unless require_scope!(:deploy)

        target = service
        authorize_service!(target, action: :deploy)

        deployment = target.deployments.find(params[:deployment_id])
        if target.git_repo.present? && deployment.commit_sha.blank?
          return render json: {
            error: "This deployment has no commit SHA and cannot be rolled back precisely",
            code: "rollback_not_precise"
          }, status: :unprocessable_entity
        end

        key = idempotency_key!
        return unless key

        result = writes.rollback(service: target, key: key, target: deployment)

        render_operation(result.operation, status: result.created ? :accepted : :ok)
      rescue AgentWrites::IdempotencyConflict
        render_idempotency_conflict
      end

      private

      def writes
        @writes ||= AgentWrites.new(organization: current_organization, actor: current_api_token)
      end

      def require_read_scope
        require_scope!(:read)
      end

      def service
        @service ||= scoped_services.find(params[:id])
      end
    end
  end
end
