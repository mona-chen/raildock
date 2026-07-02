class BackupSchedule < ApplicationRecord
  belongs_to :service
  belongs_to :storage_mount, optional: true

  validates :frequency, inclusion: { in: %w[daily weekly monthly] }
  validates :retention_count, numericality: { greater_than: 0, less_than_or_equal_to: 30 }
  validates :backup_kind, inclusion: { in: %w[database volume] }
  validate :storage_mount_matches_service

  FREQUENCY_INTERVALS = {
    "daily" => 1.day,
    "weekly" => 1.week,
    "monthly" => 1.month
  }.freeze

  def calculate_next_run
    base = [ last_run_at, Time.current ].compact.max
    base + FREQUENCY_INTERVALS[frequency]
  end

  def update_next_run!
    update!(next_run_at: calculate_next_run)
  end

  def destination_ids
    metadata&.fetch("destination_ids", []) || []
  end

  def database?
    backup_kind == "database"
  end

  def volume?
    backup_kind == "volume"
  end

  private
    def storage_mount_matches_service
      return unless volume?

      if storage_mount_id.blank?
        errors.add(:storage_mount, "is required for volume snapshots")
      elsif storage_mount&.service_id != service_id
        errors.add(:storage_mount, "must belong to this service")
      end
    end
end
