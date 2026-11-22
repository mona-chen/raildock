class BackupSchedule < ApplicationRecord
  belongs_to :service
  belongs_to :storage_mount, optional: true

  validates :frequency, inclusion: { in: %w[daily weekly monthly] }
  MAX_RETENTION = 90

  before_validation :apply_default_retention

  validates :retention_count, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_RETENTION }
  validates :backup_kind, inclusion: { in: %w[database volume] }
  validate :storage_mount_matches_service
  # Checked only when the kind changes, so bookkeeping on an existing row
  # (`update_next_run!` after a run) is never blocked.
  validate :database_kind_matches_service, if: -> { new_record? || backup_kind_changed? }

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
    # A schedule created without an explicit window gets the cadence default
    # instead of failing validation on a nil column.
    def apply_default_retention
      self.retention_count = self.class.default_retention_for(frequency) if retention_count.blank?
    end

    # A database schedule on an app service would fail on every run, so it is
    # refused up front rather than surfacing as a stream of failed backups.
    def database_kind_matches_service
      return unless database?
      return if service.nil? || service.logical_backup_supported?

      errors.add(:backup_kind, "database is only available for datastores that support export")
    end

    def storage_mount_matches_service
      return unless volume?

      if storage_mount_id.blank?
        errors.add(:storage_mount, "is required for volume snapshots")
      elsif storage_mount&.service_id != service_id
        errors.add(:storage_mount, "must belong to this service")
      end
    end
end
