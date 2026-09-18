class BackupSchedule < ApplicationRecord
  belongs_to :service
  belongs_to :storage_mount, optional: true

  validates :frequency, inclusion: { in: %w[daily weekly monthly] }
  validates :retention_count, numericality: { greater_than: 0, less_than_or_equal_to: 30 }
  validates :backup_kind, inclusion: { in: %w[database volume] }
  validate :storage_mount_matches_service

  scope :enabled, -> { where(enabled: true) }
  scope :due, -> { enabled.where(next_run_at: ..Time.current) }

  # Retention windows that mirror the platform defaults operators expect:
  # a week of dailies, a month of weeklies, two quarters of monthlies.
  DEFAULT_RETENTION = { "daily" => 7, "weekly" => 4, "monthly" => 6 }.freeze

  def self.default_retention_for(frequency)
    DEFAULT_RETENTION.fetch(frequency.to_s, 7)
  end

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

  # Expires artifacts belonging to *this* schedule, and only artifacts of its
  # own kind. Retention used to run against every completed backup of the
  # service, so a short volume-retention window could delete the only database
  # backup — and a service with no artifact left is unrecoverable.
  def enforce_retention!
    scope = service.backups
      .completed
      .where(backup_kind: backup_kind)
      .where("metadata->>'schedule_id' = ?", id.to_s)

    BackupRetention.prune(scope, keep: retention_count)
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
