class RunDueBackupsJob < ApplicationJob
  queue_as :default

  def perform
    BackupSchedule.where(next_run_at: ..Time.current).find_each do |schedule|
      backup = schedule.service.backups.create!(status: "pending", metadata: { "schedule_id" => schedule.id })
      BackupJob.perform_later(backup.id, schedule_id: schedule.id)
      schedule.update!(last_run_at: Time.current, next_run_at: schedule.calculate_next_run)
    end
  end
end
