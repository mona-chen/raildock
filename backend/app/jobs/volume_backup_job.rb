class VolumeBackupJob < ApplicationJob
  queue_as :default

  def perform(backup_id, storage_mount_id)
    backup = Backup.find(backup_id)
    mount = backup.service.storage_mounts.find(storage_mount_id)
    backup.update!(status: "running", metadata: (backup.metadata || {}).merge(
      "storage_mount_id" => mount.id, "host_path" => mount.host_path, "container_path" => mount.container_path
    ))

    path = backup_path(backup)
    FileUtils.mkdir_p(File.dirname(path))
    result = HostEngine.new(backup.service.project.server).volume_export_to(mount.host_path, path)
    raise result[:output].presence || "Volume snapshot failed" unless result[:success]

    destination_ids = backup.metadata&.fetch("destination_ids", [])
    BackupArtifactStore.new.persist!(backup, path, destination_ids: destination_ids)
  rescue => error
    backup&.update!(status: "failed", metadata: (backup.metadata || {}).merge("error" => error.message))
    File.delete(path) if defined?(path) && path && File.exist?(path)
    raise
  end

  private
    def backup_path(backup)
      root = ENV.fetch("RAILDOCK_BACKUPS_DIR", Rails.root.join("storage", "backups").to_s)
      File.join(root, backup.service_id.to_s, "#{backup.id}-volume.tar.gz")
    end
end
