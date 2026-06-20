class PostgresBaseBackupJob < ApplicationJob
  queue_as :default

  def perform(config_id)
    config = PostgresPitrConfig.find(config_id)
    return unless config.enabled?

    service = config.service
    backup = service.backups.create!(status: "running", backup_kind: "pitr_base",
      backup_destination: config.backup_destination, metadata: { "trigger" => "pitr" })
    path = Rails.root.join("tmp", "#{backup.id}-base.tar.gz").to_s
    container = "dokku.postgres.#{service.dokku_app_name}"
    command = "docker exec #{Shellwords.escape(container)} pg_basebackup -U postgres -D - -Ft -z -X stream"
    result = HostEngine.new(service.project.server).run_to_file(command, path)
    raise result[:output].presence || "PostgreSQL base backup failed" unless result[:success]

    BackupArtifactStore.new.persist!(backup, path, storage_name: "pitr/#{service.id}/base/#{Time.current.utc.strftime('%Y%m%d%H%M%S')}.tar.gz.enc")
    config.update!(last_base_backup_at: Time.current, status: "active", last_error: nil)
  rescue => error
    backup&.update!(status: "failed", metadata: (backup.metadata || {}).merge("error" => error.message))
    config&.update!(status: "error", last_error: error.message)
    raise
  ensure
    File.delete(path) if defined?(path) && path && File.exist?(path)
  end
end
