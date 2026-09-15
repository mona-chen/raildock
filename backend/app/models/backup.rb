class Backup < ApplicationRecord
  # Raised when a caller tries to delete the only completed artifact for a
  # service. Callers must acknowledge the loss explicitly (`force: true`).
  class LastCopyError < StandardError; end

  # Optional: backup artifacts outlive the services they came from. RailDock
  # nullifies service_id instead of cascading the delete, so a pre-destroy
  # snapshot (and every historical backup) stays recoverable after a service or
  # project is removed. Source identity lives in `metadata`.
  belongs_to :service, optional: true
  belongs_to :backup_destination, optional: true
  has_many :backup_copies, dependent: :destroy
  has_many :restore_drills, dependent: :destroy

  validates :status, inclusion: { in: %w[pending running completed failed] }

  scope :recent, -> { order(created_at: :desc) }
  scope :completed, -> { where(status: "completed") }
  scope :detached, -> { where(service_id: nil) }

  def self.storage_root
    ENV.fetch("RAILDOCK_BACKUPS_DIR", Rails.root.join("storage", "backups").to_s)
  end

  # True once at least one copy sits on a destination that was verified after
  # the upload — the only kind of copy that survives losing this host.
  def remote_verified?
    metadata&.fetch("remote_verified", false) ||
      backup_copies.where.not(backup_destination_id: nil).any? { |copy| copy.metadata&.fetch("verified_at", nil).present? }
  end

  def source_name
    metadata&.fetch("service_name", nil) || service&.name
  end

  def source_label
    [ metadata&.fetch("project_name", nil), source_name ].compact.join(" / ")
  end

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

  # Deletes the artifact (local file and every remote copy) and the row.
  # `force: true` acknowledges that this is the service's last restore point.
  def remove_file!(force: false)
    if !force && last_copy_for_service?
      raise LastCopyError,
        "Refusing to delete backup #{id}: it is the last completed artifact for #{source_label.presence || "this service"}"
    end

    BackupArtifactStore.new.remove!(self)
    destroy!
  end

  # True when no other completed artifact exists for the owning service.
  # Detached backups (service_id nil) have no owner to protect and are handled
  # by the API's last-backup check instead.
  def last_copy_for_service?
    return false if service_id.blank? || !completed?

    service.backups.completed.where.not(id: id).none?
  end
end
