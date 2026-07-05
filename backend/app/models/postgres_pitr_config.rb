class PostgresPitrConfig < ApplicationRecord
  belongs_to :service
  belongs_to :backup_destination

  enum :status, { pending: "pending", active: "active", error: "error", paused: "paused" }

  validates :retention_days, numericality: { in: 1..90 }
  validate :postgres_service

  private
    def postgres_service
      errors.add(:service, "must support point-in-time recovery") unless service&.subtype_record&.has_capability?(:point_in_time_recovery)
    end
end
