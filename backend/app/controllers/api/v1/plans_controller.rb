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
        AgentPlan.verify!(payload: payload, project: project, actor: current_api_token)

        removals = Array(payload[:removals]).map(&:to_s)
        if removals.any?
          return unless require_scope!(:destructive)

          unless removals_confirmed?(payload, project, removals)
            return render_removals_required(payload, project, removals)
          end
        end

        operation = Operation.create_or_find_by!(
          organization: current_organization,
          idempotency_key: "plan:#{payload[:jti]}"
        ) do |record|
          record.kind = "manifest_apply"
          record.project = project
          record.subject = project
          record.status = "pending"
          record.api_token = current_api_token
        end

        if operation.previously_new_record?
          ManifestApplyJob.perform_later(
            project.id,
            payload[:content],
            {
              allow_removals: removals.any?,
              force_destroy_data: ActiveModel::Type::Boolean.new.cast(params[:force_destroy_data]) || false,
              operation_id: operation.id,
              api_token_id: current_api_token&.id
            }
          )
        end

        render_operation(operation, status: operation.previously_new_record? ? :accepted : :ok)
      rescue AgentPlan::Expired => error
        render json: { error: error.message, code: "plan_expired" }, status: :unprocessable_entity
      rescue AgentPlan::Drifted => error
        render json: { error: error.message, code: "plan_drifted" }, status: :conflict
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

      def removals_confirmed?(payload, project, removals)
        return false unless ActiveModel::Type::Boolean.new.cast(params[:confirm_removals])

        RemovalConfirmation.verify!(
          token: params[:removal_token],
          project: project,
          digest: payload[:digest],
          removals: removals
        )
        true
      rescue RemovalConfirmation::InvalidConfirmation => error
        @removal_error = error.message
        false
      end

      def render_removals_required(payload, project, removals)
        render json: {
          error: @removal_error || "This plan removes #{removals.length} service(s): #{removals.join(', ')}. " \
            "Confirm the removals and echo the removal token.",
          code: "removals_required",
          actionable: true,
          removals: removals,
          removal_token: RemovalConfirmation.issue(
            project: project,
            digest: payload[:digest],
            removals: removals
          )
        }, status: :precondition_required
      end
    end
  end
end
