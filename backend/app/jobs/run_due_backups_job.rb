class RunDueBackupsJob < ApplicationJob
  queue_as :default

  def perform
    BackupSchedule.where(next_run_at: ..Time.current).find_each do |schedule|
      backup = create_backup(schedule)
      enqueue_job(schedule, backup)
      schedule.update!(last_run_at: Time.current, next_run_at: schedule.calculate_next_run)
    end
  end

  private
    def create_backup(schedule)
      base_metadata = { "schedule_id" => schedule.id }

      if schedule.volume?
        schedule.service.backups.create!(
          status: "pending",
          backup_kind: "volume",
          metadata: base_metadata.merge(
            "storage_mount_id" => schedule.storage_mount_id,
            "destination_ids" => schedule.destination_ids
          )
        )
      else
        schedule.service.backups.create!(
          status: "pending",
          metadata: base_metadata.merge("destination_ids" => schedule.destination_ids)
        )
      end
    end

    def enqueue_job(schedule, backup)
      if schedule.volume?
        VolumeBackupJob.perform_later(backup.id, schedule.storage_mount_id)
      else
        BackupJob.perform_later(backup.id, schedule_id: schedule.id)
      end
    end
end
