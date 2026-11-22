require "open3"

class RestoreDrillJob < ApplicationJob
  queue_as :backups

  def perform(drill_id)
    drill = RestoreDrill.find(drill_id)
    backup = drill.backup
    resource_name = "raildock-drill-#{drill.id}-#{SecureRandom.hex(3)}"
    drill.update!(status: "running", started_at: Time.current, isolated_resource_name: resource_name)

    BackupArtifactStore.new.materialize(backup) do |path|
      case backup.backup_kind
      when "database" then drill_database!(backup, path, resource_name)
      when "volume" then drill_volume!(backup, path, resource_name)
      when "pitr_base" then PostgresPhysicalRecovery.new(backup, resource_name, target_time: drill.target_time).call(path)
      else raise "Restore drills are not supported for #{backup.backup_kind} artifacts"
      end
    end

    drill.update!(status: "succeeded", checksum_verified: true, completed_at: Time.current,
      log: drill.target_time ? "Checksum verified; isolated PostgreSQL recovered to #{drill.target_time.iso8601}" : "Checksum verified and isolated restore completed successfully")
  rescue => error
    drill&.update!(status: "failed", completed_at: Time.current, log: error.message)
    raise
  end

  private
    def drill_database!(backup, path, resource_name)
      service = backup.service
      raise "Automated database drills require a service with backup/restore capabilities" unless service.subtype_record&.has_capability?(:backup) && service.subtype_record&.has_capability?(:restore)

      engine = DokkuEngine.new(service.project.server)
      drill_service = OpenStruct.new(subtype: service.subtype, dokku_app_name: resource_name)
      created = engine.datastore_create(drill_service)
      raise created[:output].presence || "Could not create isolated drill database" unless created[:success]

      imported = engine.datastore_import_from(drill_service, path)
      raise imported[:output].presence || "Could not import backup into isolated drill database" unless imported[:success]

      plugin = service.subtype_record.dokku_plugin.presence || service.subtype
      container = "dokku.#{plugin}.#{resource_name}"
      healthy = HostEngine.new(service.project.server).run(readiness_command(plugin, container))
      raise healthy[:output].presence || "Isolated #{service.subtype_record.name} did not become ready" unless healthy[:success]
    ensure
      engine&.datastore_destroy(drill_service) if created && created[:success]
    end

    # Readiness differs per engine. Drills used to run `pg_isready` against a
    # `dokku.postgres.*` container for every datastore, so MySQL, MariaDB,
    # MongoDB and Redis drills failed every week regardless of the artifact.
    # The import itself already proved the dump loads; this proves the server
    # is still answering afterwards.
    def readiness_command(plugin, container)
      target = Shellwords.escape(container)
      probe = case plugin
      when "postgres"
        "pg_isready -U postgres"
      when "mysql"
        "mysqladmin ping -h 127.0.0.1 --silent"
      when "mariadb"
        "sh -c 'mariadb-admin ping -h 127.0.0.1 --silent 2>/dev/null || mysqladmin ping -h 127.0.0.1 --silent'"
      when "mongo"
        "sh -c 'mongosh --quiet --eval \"db.runCommand({ ping: 1 }).ok\" 2>/dev/null || mongo --quiet --eval \"db.runCommand({ ping: 1 }).ok\"'"
      end

      return "docker exec #{target} #{probe}" if probe

      # Engines without an unauthenticated probe (Redis requires its password
      # for PING) are checked for a running container after the import.
      "test \"$(docker inspect -f '{{.State.Running}}' #{target})\" = true"
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
end
