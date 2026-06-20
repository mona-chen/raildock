class RunRecoveryDrillsJob < ApplicationJob
  queue_as :default

  def perform
    Service.find_each do |service|
      %w[database volume pitr_base].each do |kind|
        backup = service.backups.completed.where(backup_kind: kind).order(created_at: :desc).first
        next unless backup
        next if backup.restore_drills.where(created_at: 7.days.ago..).exists?

        drill = backup.restore_drills.create!
        RestoreDrillJob.perform_later(drill.id)
      end
    end
  end
end
