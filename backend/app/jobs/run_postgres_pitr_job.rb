class RunPostgresPitrJob < ApplicationJob
  queue_as :default

  def perform
    PostgresPitrConfig.where(enabled: true).find_each do |config|
      PostgresWalArchiveJob.perform_later(config.id)
      if config.last_base_backup_at.nil? || config.last_base_backup_at < 24.hours.ago
        PostgresBaseBackupJob.perform_later(config.id)
      end
      config.service.backups.completed.where(backup_kind: %w[pitr_base wal])
        .where(created_at: ...config.retention_days.days.ago).find_each(&:remove_file!)
    end
  end
end
