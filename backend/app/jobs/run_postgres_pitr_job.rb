class RunPostgresPitrJob < ApplicationJob
  include BackupQueueAware
  queue_as :backups

  # An artifact still pending/running means a job is already working on this
  # config. The window keeps a job killed mid-flight from wedging PITR forever.
  IN_FLIGHT_WINDOW = 1.hour

  def perform
    # Do not fan work out while the backups queue is already draining: the PITR
    # child jobs would land behind the backlog and multiply it.
    return if backups_backlogged?

    PostgresPitrConfig.where(enabled: true).find_each do |config|
      # Retention is independent of whether archiving is being retried: prune
      # even while the config is backing off.
      prune(config)

      next unless config.due_for_retry?

      PostgresWalArchiveJob.perform_later(config.id) unless archive_in_flight?(config)
      PostgresBaseBackupJob.perform_later(config.id) if base_backup_due?(config) && !base_backup_in_flight?(config)
    end
  end

  private
    def base_backup_due?(config)
      config.last_base_backup_at.nil? || config.last_base_backup_at < 24.hours.ago
    end

    def archive_in_flight?(config)
      artifact_in_flight?(config, "wal") || backup_job_enqueued?(PostgresWalArchiveJob, config.id)
    end

    def base_backup_in_flight?(config)
      artifact_in_flight?(config, "pitr_base") || backup_job_enqueued?(PostgresBaseBackupJob, config.id)
    end

    def artifact_in_flight?(config, backup_kind)
      config.service.backups
        .where(backup_kind: backup_kind, status: %w[pending running])
        .where(created_at: IN_FLIGHT_WINDOW.ago..)
        .exists?
    end

    # PITR retention must never expire the newest base backup or the newest WAL
    # segment: a window that has aged past `retention_days` because archiving
    # stalled (or the schedule was paused) would otherwise be deleted in full,
    # leaving the datastore with no recovery points at all.
    def prune(config)
      scope = config.service.backups.completed
        .where(backup_kind: %w[pitr_base wal])
        .where(created_at: ...config.retention_days.days.ago)
      BackupRetention.prune(scope, keep: 1)
    end
end
