class BackupJob < ApplicationJob
  queue_as :default

  def perform(backup_id, schedule_id: nil)
    backup = Backup.find(backup_id)
    service = backup.service
    path = backup_path(backup)
    FileUtils.mkdir_p(File.dirname(path))
    backup.update!(status: "running")

    result = DokkuEngine.new(service.project.server).datastore_export_to(service, path)
    raise result[:output].presence || "Backup export failed" unless result[:success]

    BackupArtifactStore.new.persist!(backup, path)
    enforce_retention(service, schedule_id)
    record_success(backup)
  rescue => e
    backup&.update!(status: "failed", metadata: (backup.metadata || {}).merge("error" => e.message))
    File.delete(path) if defined?(path) && path && File.exist?(path)
    raise
  end

  private
    def backup_path(backup)
      root = ENV.fetch("RAILDOCK_BACKUPS_DIR", Rails.root.join("storage", "backups").to_s)
      File.join(root, backup.service_id.to_s, "#{backup.id}-#{Time.current.utc.strftime('%Y%m%d%H%M%S')}.dump")
    end

    def enforce_retention(service, schedule_id)
      schedule = service.backup_schedules.find_by(id: schedule_id)
      return unless schedule

      service.backups.completed.order(created_at: :desc).offset(schedule.retention_count).find_each(&:remove_file!)
      schedule.update!(last_run_at: Time.current, next_run_at: schedule.calculate_next_run)
    end

    def record_success(backup)
      ActivityEvent.create!(
        project: backup.service.project,
        service_name: backup.service.name,
        action: :created,
        message: "Created and verified backup for #{backup.service.name}",
        metadata: { backup_id: backup.id, checksum: backup.metadata["checksum"] }
      )
    end
end
