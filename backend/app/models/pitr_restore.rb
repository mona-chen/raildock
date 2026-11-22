# A point-in-time recovery of a PostgreSQL service into a NEW service in the
# same project/environment (Railway-style staged restore). The source service
# is only read through its archived base backup and WAL; it is never written.
class PitrRestore < ApplicationRecord
  belongs_to :source_service, class_name: "Service", optional: true
  belongs_to :restored_service, class_name: "Service", optional: true
  belongs_to :backup, optional: true
  belongs_to :project

  enum :status, { pending: "pending", running: "running", succeeded: "succeeded", failed: "failed" }

  scope :recent, -> { order(created_at: :desc) }

  validates :target_time, :service_name, presence: true

  def as_json(options = {})
    super(options.merge(except: [ :metadata ])).merge(
      "restored_service_name" => restored_service&.name,
      "table_count" => metadata&.dig("table_count")
    )
  end
end
