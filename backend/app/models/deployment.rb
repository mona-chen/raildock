class Deployment < ApplicationRecord
  belongs_to :service

  validates :status, inclusion: { in: %w[pending building deploying succeeded failed cancelled] }

  enum :status, {
    pending: "pending",
    building: "building",
    deploying: "deploying",
    succeeded: "succeeded",
    failed: "failed",
    cancelled: "cancelled"
  }

  scope :cancellable, -> { where(status: %w[pending building deploying]) }
  scope :pending, -> { where(status: "pending") }

  def self.create_idempotently!(service:, key:, attributes:)
    deployment = service.deployments.create_or_find_by!(idempotency_key: key) do |record|
      record.assign_attributes(attributes)
    end

    [ deployment, deployment.previously_new_record? ]
  end

  def cancellable?
    pending? || building? || deploying?
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
end
