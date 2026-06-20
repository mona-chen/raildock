require "open3"

class RestoreDrillJob < ApplicationJob
  queue_as :default

  def perform(drill_id)
    drill = RestoreDrill.find(drill_id)
    backup = drill.backup
    resource_name = "raildock-drill-#{drill.id}-#{SecureRandom.hex(3)}"
    drill.update!(status: "running", started_at: Time.current, isolated_resource_name: resource_name)

    BackupArtifactStore.new.materialize(backup) do |path|
      case backup.backup_kind
      when "database" then drill_database!(backup, path, resource_name)
      when "volume" then drill_volume!(backup, path, resource_name)
      when "pitr_base" then drill_archive!(path)
      else raise "Restore drills are not supported for #{backup.backup_kind} artifacts"
      end
    end

    drill.update!(status: "succeeded", checksum_verified: true, completed_at: Time.current,
      log: "Checksum verified and isolated restore completed successfully")
  rescue => error
    drill&.update!(status: "failed", completed_at: Time.current, log: error.message)
    raise
  end

  private
    def drill_database!(backup, path, resource_name)
      service = backup.service
      raise "Automated database drills currently require PostgreSQL" unless service.subtype == "postgres"

      engine = DokkuEngine.new(service.project.server)
      created = engine.postgres_create(resource_name)
      raise created[:output].presence || "Could not create isolated PostgreSQL drill database" unless created[:success]

      imported = engine.run_with_file("postgres:import #{Shellwords.escape(resource_name)}", path)
      raise imported[:output].presence || "Could not import backup into isolated PostgreSQL" unless imported[:success]

      container = "dokku.postgres.#{resource_name}"
      healthy = HostEngine.new(service.project.server).run("docker exec #{Shellwords.escape(container)} pg_isready -U postgres")
      raise healthy[:output].presence || "Isolated PostgreSQL did not become ready" unless healthy[:success]
    ensure
      engine&.postgres_destroy(resource_name)
    end

    def drill_volume!(backup, path, resource_name)
      host = HostEngine.new(backup.service.project.server)
      restored = host.volume_import_from(resource_name, path)
      raise restored[:output].presence || "Could not restore isolated Docker volume" unless restored[:success]

      verified = host.run("docker run --rm -v #{Shellwords.escape(resource_name)}:/source:ro alpine:3.20 tar -C /source -cf /dev/null .")
      raise verified[:output].presence || "Could not read isolated restored volume" unless verified[:success]
    ensure
      host&.run("docker volume rm -f #{Shellwords.escape(resource_name)}")
    end

    def drill_archive!(path)
      _output, error, status = Open3.capture3("tar", "-tzf", path)
      raise error.presence || "Physical base backup archive is invalid" unless status.success?
    end
end
