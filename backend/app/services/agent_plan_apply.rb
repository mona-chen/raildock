# Applies a reviewed plan for the HTTP and MCP surfaces.
#
# The caller decodes the plan and authorizes the project; this object enforces
# the plan's own invariants (base digest, issuing token, removal confirmation)
# and starts exactly one manifest apply per plan.
class AgentPlanApply
  class RemovalRequired < StandardError
    attr_reader :removals, :removal_token

    def initialize(message, removals:, removal_token:)
      super(message)
      @removals = removals
      @removal_token = removal_token
    end
  end

  Result = Struct.new(:operation, :created, keyword_init: true)

  def initialize(organization:, actor: nil)
    @organization = organization
    @actor = actor
  end

  def call(payload:, project:, confirm_removals: false, removal_token: nil, force_destroy_data: false)
    AgentPlan.verify!(payload: payload, project: project, actor: actor)

    removals = Array(payload[:removals]).map(&:to_s)
    if removals.any? && !removals_confirmed?(payload, project, removals, confirm_removals, removal_token)
      raise RemovalRequired.new(
        @removal_error || "This plan removes #{removals.length} service(s): #{removals.join(', ')}. " \
          "Confirm the removals and echo the removal token.",
        removals: removals,
        removal_token: RemovalConfirmation.issue(project: project, digest: payload[:digest], removals: removals)
      )
    end

    operation = Operation.create_or_find_by!(
      organization: organization,
      idempotency_key: "plan:#{payload[:jti]}"
    ) do |record|
      record.kind = "manifest_apply"
      record.project = project
      record.subject = project
      record.status = "pending"
      record.api_token = actor
    end

    if operation.previously_new_record?
      ManifestApplyJob.perform_later(
        project.id,
        payload[:content],
        {
          allow_removals: removals.any?,
          force_destroy_data: ActiveModel::Type::Boolean.new.cast(force_destroy_data) || false,
          operation_id: operation.id,
          api_token_id: actor&.id
        }
      )
    end

    Result.new(operation: operation, created: operation.previously_new_record?)
  end

  private

  attr_reader :organization, :actor

  def removals_confirmed?(payload, project, removals, confirm_removals, removal_token)
    return false unless ActiveModel::Type::Boolean.new.cast(confirm_removals)

    RemovalConfirmation.verify!(
      token: removal_token,
      project: project,
      digest: payload[:digest],
      removals: removals
    )
    true
  rescue RemovalConfirmation::InvalidConfirmation => error
    @removal_error = error.message
    false
  end
end
