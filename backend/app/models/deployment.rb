class Deployment < ApplicationRecord
  belongs_to :service

  validates :status, inclusion: { in: %w[pending building deploying succeeded failed cancelled] }
  validates :kind, inclusion: { in: %w[deploy restart rebuild env_sync] }

  enum :status, {
    pending: "pending",
    building: "building",
    deploying: "deploying",
    succeeded: "succeeded",
    failed: "failed",
    cancelled: "cancelled"
  }

  enum :kind, {
    deploy: "deploy",
    restart: "restart",
    rebuild: "rebuild",
    env_sync: "env_sync"
  }

  scope :cancellable, -> { where(status: %w[pending building deploying]) }
  scope :pending, -> { where(status: "pending") }
  scope :restarts, -> { where(kind: %w[restart env_sync]) }

  def self.create_idempotently!(service:, key:, attributes:)
    deployment = service.deployments.create_or_find_by!(idempotency_key: key) do |record|
      record.assign_attributes(attributes)
    end

    [ deployment, deployment.previously_new_record? ]
  end

  def cancellable?
    pending? || building? || deploying?
  end

  def restart?
    kind == "restart" || kind == "env_sync"
  end

  def cancel!(message: "Cancelled by user")
    cancelled_at = Time.current
    updated = self.class.cancellable.where(id: id).update_all(
      status: self.class.statuses.fetch("cancelled"),
      deploy_log: [ deploy_log.presence, message ].compact.join("\n\n"),
      completed_at: cancelled_at,
      updated_at: cancelled_at
    )
    return false unless updated == 1

    reload

    service.reload
    active = service.deployments.cancellable.exists?
    previous_success = service.deployments.succeeded.where.not(id: id).exists?
    service.update!(status: active ? :deploying : (previous_success ? :running : :error))

    DeploymentsChannel.broadcast_to(service, {
      deployment_id: id,
      status: "cancelled",
      message: message,
      completed_at: completed_at.iso8601
    })

    ActivityEvent.create!(
      project: service.project,
      service_name: service.name,
      action: :warning,
      message: "Deployment cancelled for #{service.name}: #{message}"
    )

    true
  end

  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end

  def append_log_chunk!(chunk)
    redacted = LogRedactor.redact(chunk)
    with_lock do
      self.event_sequence += 1
      self.deploy_log = "#{deploy_log}#{redacted}"
      save!
    end
    redacted
  end

  def next_event_sequence!
    with_lock do
      self.event_sequence += 1
      save!
      event_sequence
    end
  end

  def as_json(options = {})
    json = super(options)
    json["deploy_log"] = LogRedactor.redact(json["deploy_log"]) if json["deploy_log"].present?
    json["build_log"] = LogRedactor.redact(json["build_log"]) if json["build_log"].present?
    json
  end
end
