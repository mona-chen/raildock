class Backup < ApplicationRecord
  belongs_to :service
  belongs_to :backup_destination, optional: true
  has_many :backup_copies, dependent: :destroy
  has_many :restore_drills, dependent: :destroy

  validates :status, inclusion: { in: %w[pending running completed failed] }

  scope :recent, -> { order(created_at: :desc) }
  scope :completed, -> { where(status: "completed") }

  enum :backup_kind, { database: "database", volume: "volume", pitr_base: "pitr_base", wal: "wal" }, prefix: true

  def complete!(path, destination_ids: [])
    BackupArtifactStore.new.persist!(self, path, destination_ids: destination_ids)
  end

  def available?
    completed? && (local_copy_available? || remote_copy_available?)
  end

  def local_copy_available?
    file_path.present? && File.file?(file_path)
  end

  def remote_copy_available?
    backup_copies.completed.exists? || storage_key.present?
  end

  def integrity_valid?
    expected = metadata&.fetch("checksum", nil)
    return false if expected.blank? || file_path.blank? || !File.file?(file_path)

    ActiveSupport::SecurityUtils.secure_compare(expected, Digest::SHA256.file(file_path).hexdigest)
  rescue Errno::ENOENT
    false
  end

  def completed?
    status == "completed"
  end

  def remove_file!
    BackupArtifactStore.new.remove!(self)
    destroy!
  end
end
