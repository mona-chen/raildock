class RunPostgresPitrJob < ApplicationJob
  queue_as :default

  def perform
    PostgresPitrConfig.where(enabled: true).find_each do |config|
      PostgresWalArchiveJob.perform_later(config.id)
      if config.last_base_backup_at.nil? || config.last_base_backup_at < 24.hours.ago
        PostgresBaseBackupJob.perform_later(config.id)
      end
      # PITR retention must never expire the newest base backup or the newest
      # WAL segment: a window that has aged past `retention_days` because
      # archiving stalled (or the schedule was paused) would otherwise be
      # deleted in full, leaving the datastore with no recovery points at all.
      scope = config.service.backups.completed
        .where(backup_kind: %w[pitr_base wal])
        .where(created_at: ...config.retention_days.days.ago)
      BackupRetention.prune(scope, keep: 1)
    end
  end
end
