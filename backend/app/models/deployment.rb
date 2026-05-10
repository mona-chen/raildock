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

  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end
end
