# Starts asynchronous service work for the agent surface.
#
# The operation is keyed by the caller's Idempotency-Key and the deployment by
# the same value scoped to the organization, so a retry attaches to the work
# already started instead of building a second deployment.
class AgentWrites
  class IdempotencyConflict < StandardError; end

  Result = Struct.new(:operation, :created, keyword_init: true)

  def initialize(organization:, actor: nil)
    @organization = organization
    @actor = actor
  end

  def deploy(service:, key:, branch: nil, commit_sha: nil, commit_message: nil)
    start(
      service: service,
      key: key,
      kind: "deploy",
      fingerprint: "deploy:#{service.id}",
      deployment_attributes: {
        kind: "deploy",
        status: "pending",
        started_at: Time.current,
        branch: branch.presence || service.branch || "main",
        commit_sha: commit_sha,
        commit_message: commit_message,
        triggered_by: "manual"
      }
    ) do |deployment|
      DeploymentJob.perform_later(service.id, deployment.id, api_token_id: actor&.id)
      service.update!(status: :deploying)
      ActivityEvent.create!(
        project: service.project,
        service_name: service.name,
        action: :deployed,
        message: "Deployment triggered for #{service.name}",
        api_token: actor
      )
    end
  end

  def restart(service:, key:)
    start(
      service: service,
      key: key,
      kind: "restart",
      fingerprint: "restart:#{service.id}",
      deployment_attributes: {
        kind: "restart",
        status: "pending",
        started_at: Time.current,
        branch: service.branch,
        triggered_by: "manual",
        build_log: "",
        deploy_log: ""
      }
    ) do |deployment|
      RestartJob.perform_later(
        service.id,
        idempotency_key: deployment.idempotency_key,
        api_token_id: actor&.id
      )
    end
  end

  def rollback(service:, key:, target:)
    start(
      service: service,
      key: key,
      kind: "rollback",
      fingerprint: "rollback:#{service.id}:#{target.id}",
      deployment_attributes: {
        kind: "deploy",
        status: "pending",
        started_at: Time.current,
        branch: target.branch || service.branch || "main",
        commit_sha: target.commit_sha,
        commit_message: "Rollback: #{target.commit_message.presence || target.commit_sha.to_s.first(7)}",
        triggered_by: "rollback"
      }
    ) do |deployment|
      DeploymentJob.perform_later(service.id, deployment.id, api_token_id: actor&.id)
      service.update!(status: :deploying)
      ActivityEvent.create!(
        project: service.project,
        service_name: service.name,
        action: :deployed,
        message: "Rollback to #{target.commit_sha || target.branch} for #{service.name}",
        api_token: actor
      )
    end
  end

  private

  attr_reader :organization, :actor

  def start(service:, key:, kind:, fingerprint:, deployment_attributes:)
    if (existing = find_operation(key))
      return replay(existing, fingerprint)
    end

    deployment, created = Deployment.create_idempotently!(
      service: service,
      key: "agent-#{organization.id}-#{key}",
      attributes: deployment_attributes
    )

    operation = Operation.create_or_find_by!(
      organization: organization,
      idempotency_key: key
    ) do |record|
      record.kind = kind
      record.project = service.project
      record.service = service
      record.subject = deployment
      record.request_fingerprint = fingerprint
      record.api_token = actor
    end

    raise IdempotencyConflict unless operation.request_fingerprint == fingerprint

    yield(deployment) if created

    Result.new(operation: operation, created: created)
  end

  def replay(operation, fingerprint)
    raise IdempotencyConflict unless operation.request_fingerprint == fingerprint

    Result.new(operation: operation, created: false)
  end

  def find_operation(key)
    Operation.find_by(organization: organization, idempotency_key: key)
  end
end
