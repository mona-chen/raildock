class PostgresPitrConfig < ApplicationRecord
  belongs_to :service
  belongs_to :backup_destination

  enum :status, { pending: "pending", active: "active", error: "error", paused: "paused" }

  # The scheduler ticks every minute. A config that just failed — typically
  # because its destination is unreachable — must not be retried on every tick,
  # or one dead endpoint turns into an archive attempt per minute forever and
  # buries the backup queue. Retry on a window instead, which also lets the
  # config recover on its own once the endpoint is back.
  RETRY_BACKOFF = 15.minutes

  validates :retention_days, numericality: { in: 1..90 }
  validate :postgres_service

  def due_for_retry?(now: Time.current)
    !error? || updated_at <= now - RETRY_BACKOFF
  end

  private
    def postgres_service
      errors.add(:service, "must support point-in-time recovery") unless service&.subtype_record&.has_capability?(:point_in_time_recovery)
    end
end
