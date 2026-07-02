class BackupCopy < ApplicationRecord
  belongs_to :backup
  belongs_to :backup_destination, optional: true

  enum :kind, {
    local: "local",
    s3: "s3",
    r2: "r2"
  }, prefix: true

  enum :status, {
    pending: "pending",
    completed: "completed",
    failed: "failed"
  }

  validates :kind, inclusion: { in: kinds.keys }
  validates :status, inclusion: { in: statuses.keys }
  validates :size, numericality: { greater_than_or_equal_to: 0 }

  def local?
    backup_destination.nil?
  end

  def destination_name
    backup_destination&.name || "local"
  end
end
