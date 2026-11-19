module Api
  module V1
    # Shared behavior for the agent-facing surface. A request may authenticate
    # with a user JWT (for previewing and tests) or with an API token; scopes and
    # bindings only apply to the token.
    class BaseController < Api::BaseController
      include Authorizable

      before_action :require_organization_context!

      private

      def require_organization_context!
        return if current_organization

        render json: {
          error: "X-Organization-ID is required for the v1 API",
          code: "organization_required"
        }, status: :bad_request
      end

      def require_scope!(scope)
        return true unless current_api_token
        return true if current_api_token.allows?(scope)

        render json: {
          error: "This token lacks the #{scope} scope",
          code: "scope_denied",
          required_scope: scope.to_s,
          granted_scopes: current_api_token.scopes
        }, status: :forbidden
        false
      end

      # Tokens can be bound to a project and an environment. Reading through
      # this scope makes an out-of-binding resource a 404 instead of a 403, so
      # a token cannot probe for ids it is not allowed to see.
      def scoped_projects
        projects = super
        projects = projects.where(id: current_api_token.project_id) if current_api_token&.project_id
        projects
      end

      def scoped_services
        services = Service.where(project_id: scoped_projects.select(:id))
        services = services.where(environment_id: current_api_token.environment_id) if current_api_token&.environment_id
        services
      end

      def scoped_servers
        Server.where(organization_id: current_organization.id)
      end

      def scoped_operations
        Operation.where(organization: current_organization)
      end

      # Async writes must be safe to retry: an agent that loses the response can
      # send the same key again and attach to the work already started.
      def idempotency_key!
        key = request.headers["Idempotency-Key"].to_s.strip

        if key.blank?
          render json: {
            error: "Idempotency-Key header is required for this write",
            code: "idempotency_key_required"
          }, status: :bad_request
          return nil
        end

        if key.length > 140
          render json: {
            error: "Idempotency-Key must be at most 140 characters",
            code: "idempotency_key_invalid"
          }, status: :unprocessable_entity
          return nil
        end

        key
      end

      def find_operation(key)
        Operation.find_by(organization: current_organization, idempotency_key: key)
      end

      def render_idempotency_conflict
        render json: {
          error: "Idempotency-Key was already used for a different request",
          code: "idempotency_key_reused"
        }, status: :unprocessable_entity
      end

      def render_operation(operation, status:)
        render json: { operation: OperationPresenter.new(operation).as_json }, status: status
      end
    end
  end
end
