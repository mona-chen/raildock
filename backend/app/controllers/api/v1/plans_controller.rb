module Api
  module V1
    # Plans are reviewed before they are applied. `create` diffs a manifest and
    # returns a signed, expiring token; `apply` only accepts that token, so the
    # exact content and removal list cannot be swapped between review and write.
    class PlansController < BaseController
      def create
        return unless require_scope!(:read)

        project = scoped_projects.find(plan_params[:project_id])
        authorize_project!(project, action: :read)

        content = plan_params[:content].presence || project.manifest_content
        if content.blank?
          return render json: {
            error: "No manifest configured. Supply plan.content.",
            code: "manifest_missing"
          }, status: :unprocessable_entity
        end

        plan = AgentPlan.build(
          project: project,
          content: content,
          format: plan_params[:format],
          actor: current_api_token
        )

        render json: { plan: plan.as_json }, status: :created
      rescue AgentPlan::Invalid => error
        render json: { error: error.message, code: "invalid_manifest" }, status: :unprocessable_entity
      end

      def apply
        return unless require_scope!("config:write")

        payload = AgentPlan.decode!(plan_token)
        project = scoped_projects.find_by(id: payload[:project_id])
        return render json: { error: "Not found" }, status: :not_found unless project

        authorize_project!(project, action: :update)

        if Array(payload[:removals]).any?
          return unless require_scope!(:destructive)
        end

        result = AgentPlanApply.new(
          organization: current_organization,
          actor: current_api_token
        ).call(
          payload: payload,
          project: project,
          confirm_removals: params[:confirm_removals],
          removal_token: params[:removal_token],
          force_destroy_data: params[:force_destroy_data]
        )

        render_operation(result.operation, status: result.created ? :accepted : :ok)
      rescue AgentPlan::Expired => error
        render json: { error: error.message, code: "plan_expired" }, status: :unprocessable_entity
      rescue AgentPlan::Drifted => error
        render json: { error: error.message, code: "plan_drifted" }, status: :conflict
      rescue AgentPlanApply::RemovalRequired => error
        render json: {
          error: error.message,
          code: "removals_required",
          actionable: true,
          removals: error.removals,
          removal_token: error.removal_token
        }, status: :precondition_required
      rescue AgentPlan::Invalid => error
        render json: { error: error.message, code: "invalid_plan" }, status: :unprocessable_entity
      end

      private

      def plan_params
        source = params[:plan]
        source = params unless source.respond_to?(:permit)
        source.permit(:project_id, :content, :format)
      end

      def plan_token
        value = params[:plan]
        return value if value.is_a?(String)

        value&.[](:id) || params[:plan_id]
      end
    end
  end
end
