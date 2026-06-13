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

  def self.create_idempotently!(service:, key:, attributes:)
    deployment = service.deployments.create_or_find_by!(idempotency_key: key) do |record|
      record.assign_attributes(attributes)
    end

    [ deployment, deployment.previously_new_record? ]
  end

  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end
end
