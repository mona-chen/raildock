class BackupSchedule < ApplicationRecord
  belongs_to :service

  validates :frequency, inclusion: { in: %w[daily weekly monthly] }
  validates :retention_count, numericality: { greater_than: 0, less_than_or_equal_to: 30 }

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
end
