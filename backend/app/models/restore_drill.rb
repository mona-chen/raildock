class RestoreDrill < ApplicationRecord
  belongs_to :backup

  enum :status, { pending: "pending", running: "running", succeeded: "succeeded", failed: "failed" }

  scope :recent, -> { order(created_at: :desc) }
end
