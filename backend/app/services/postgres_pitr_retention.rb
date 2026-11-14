# Physical recovery needs every WAL segment following its retained base backup.
# Use capture start times conservatively; do not prune individual WAL files by count.
class PostgresPitrRetention
  def initialize(config)
    @config = config
  end

  def prune!
    backups = @config.service.backups.completed
    bases = backups.where(backup_kind: "pitr_base").order(:created_at, :id).to_a
    cutoff = @config.retention_days.days.ago
    anchor = bases.select { |base| base.created_at <= cutoff }.last || bases.first
    return unless anchor # Without a base, do not discard any possible recovery data.

    backups.where(backup_kind: %w[pitr_base wal]).where(created_at: ...anchor.created_at).find_each do |backup|
      next if BackupRetention::PROTECTED_TRIGGERS.include?(backup.metadata["trigger"])
      next if backup.metadata["wal_name"].to_s.end_with?(".history")

      backup.remove_file!
    rescue Backup::LastCopyError => error
      Rails.logger.warn "PITR retention: #{error.message}"
    end
  end
end
