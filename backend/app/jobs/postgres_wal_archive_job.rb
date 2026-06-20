class PostgresWalArchiveJob < ApplicationJob
  queue_as :default

  WAL_NAME = /\A[0-9A-F]{24}(?:\.[0-9A-F]{8}\.backup)?\z/

  def perform(config_id)
    config = PostgresPitrConfig.find(config_id)
    return unless config.enabled?

    service = config.service
    host = HostEngine.new(service.project.server)
    container = "dokku.postgres.#{service.dokku_app_name}"
    listing = host.run("docker exec #{Shellwords.escape(container)} find #{PostgresPitrConfigurator::ARCHIVE_DIRECTORY} -maxdepth 1 -type f -printf '%f\\n'")
    raise listing[:output].presence || "Could not list archived WAL files" unless listing[:success]

    listing[:output].lines.map(&:strip).grep(WAL_NAME).sort.each do |wal_name|
      archive_one!(config, host, container, wal_name)
    end
    config.update!(status: "active", last_error: nil)
  rescue => error
    config&.update!(status: "error", last_error: error.message)
    raise
  end

  private
    def archive_one!(config, host, container, wal_name)
      service = config.service
      backup = service.backups.create!(status: "running", backup_kind: "wal",
        backup_destination: config.backup_destination, metadata: { "wal_name" => wal_name, "trigger" => "pitr" })
      path = Rails.root.join("tmp", "#{backup.id}-#{wal_name}").to_s
      command = "docker exec #{Shellwords.escape(container)} cat #{PostgresPitrConfigurator::ARCHIVE_DIRECTORY}/#{wal_name}"
      result = host.run_to_file(command, path)
      raise result[:output].presence || "Could not read WAL segment #{wal_name}" unless result[:success]

      BackupArtifactStore.new.persist!(backup, path, storage_name: "pitr/#{service.id}/wal/#{wal_name}.enc")
      deletion = host.run("docker exec #{Shellwords.escape(container)} rm -f #{PostgresPitrConfigurator::ARCHIVE_DIRECTORY}/#{wal_name}")
      raise deletion[:output].presence || "WAL uploaded but local cleanup failed" unless deletion[:success]
      config.update!(last_wal_archived_at: Time.current)
    rescue => error
      backup&.update!(status: "failed", metadata: (backup.metadata || {}).merge("error" => error.message))
      raise
    ensure
      File.delete(path) if defined?(path) && path && File.exist?(path)
    end
end
