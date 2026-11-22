require "fileutils"
require "shellwords"

# Recovers a PostgreSQL service to a chosen moment into a NEW Dokku postgres
# service (Railway-style staged restore). The source service is only read
# through its archived base backup and WAL; nothing is ever written to it.
#
# 1. `PostgresPhysicalRecovery` boots a private, network-less PostgreSQL from
#    the base backup and replays WAL up to `target_time`, then proves it
#    promoted and answers SQL.
# 2. While that instance is still up, its database is dumped and loaded into
#    the new service with Dokku's own `postgres:import`.
# 3. The new service must answer with the same number of user tables before
#    the restore is reported as succeeded.
#
# On failure only what this job created is removed: the isolated instance and
# the new, never-live datastore/service.
class PitrRestoreJob < ApplicationJob
  queue_as :backups

  retry_on ServiceOperationLock::Busy, wait: 10.seconds, attempts: 30

  def perform(restore_id)
    restore = PitrRestore.find(restore_id)
    return if restore.succeeded? || restore.failed?

    service = restore.restored_service or raise "The new service was removed before the recovery finished"
    source = restore.source_service or raise "The source service no longer exists"
    backup = restore.backup or raise "The base backup has expired"

    ServiceOperationLock.with(service) do
      recover!(restore, source, service, backup)
    end
  rescue ServiceOperationLock::Busy
    raise
  rescue => error
    fail!(restore, error) if restore
    raise
  end

  # Dokku's postgres plugin names the database after the service, with `.`
  # and `-` replaced by `_` (`get_database_name`).
  def self.database_name(service)
    service.dokku_app_name.to_s.tr(".-", "__")
  end

  private
    def recover!(restore, source, service, backup)
      server = service.project.server
      engine = DokkuEngine.new(server)
      resource_name = "raildock-pitr-#{restore.id}-#{SecureRandom.hex(3)}"
      restore.update!(status: "running", started_at: Time.current, isolated_resource_name: resource_name,
        log: "Replaying WAL up to #{restore.target_time.utc.iso8601} in an isolated PostgreSQL")

      source_db = self.class.database_name(source)
      table_count = nil

      BackupArtifactStore.new.materialize(backup) do |path|
        PostgresPhysicalRecovery.new(backup, resource_name, target_time: restore.target_time).call(path) do |recovery|
          raise "The recovered cluster has no database named #{source_db}" unless recovery.database_exists?(source_db)

          table_count = recovery.table_count(source_db)
          restore.update!(log: "Recovered #{table_count} tables; copying them into #{service.name}")
          copy_into_new_service!(restore, recovery, source_db, service, engine)
        end
      end

      verify_new_service!(server, service, table_count)
      service.update!(status: "running")
      restore.update!(status: "succeeded", completed_at: Time.current,
        metadata: restore.metadata.merge("table_count" => table_count),
        log: "#{service.name} holds #{source.name} as of #{restore.target_time.utc.iso8601} (#{table_count} tables verified)")
      ActivityEvent.create!(project: service.project, service_name: service.name, action: :created,
        message: "Recovered #{source.name} to #{restore.target_time.utc.iso8601} into new service #{service.name}",
        metadata: { "pitr_restore_id" => restore.id, "source_service_id" => source.id, "backup_id" => backup.id,
                    "target_time" => restore.target_time.utc.iso8601, "table_count" => table_count })
    end

    def copy_into_new_service!(restore, recovery, source_db, service, engine)
      dump_path = Rails.root.join("tmp", "pitr-restore-#{restore.id}-#{SecureRandom.hex(4)}.dump").to_s
      recovery.dump_database(source_db, dump_path)

      created = engine.datastore_create(service)
      raise created[:output].presence || "Could not create PostgreSQL service #{service.dokku_app_name}" unless created[:success]
      restore.update!(metadata: restore.metadata.merge("datastore_created" => true))

      imported = engine.datastore_import_from(service, dump_path)
      raise imported[:output].presence || "Could not load the recovered data into #{service.name}" unless imported[:success]
    ensure
      FileUtils.rm_f(dump_path) if dump_path
    end

    # Success means the new service answers SQL and carries every user table
    # the recovered instance had — not merely that the import exited 0.
    def verify_new_service!(server, service, expected_tables)
      container = Shellwords.escape("dokku.postgres.#{service.dokku_app_name}")
      database = Shellwords.escape(self.class.database_name(service))
      sql = Shellwords.escape(PostgresPhysicalRecovery::USER_TABLE_COUNT_SQL)
      result = HostEngine.new(server).run("docker exec #{container} psql -U postgres -d #{database} -v ON_ERROR_STOP=1 -Atqc #{sql}")
      raise result[:output].presence || "#{service.name} did not answer after the import" unless result[:success]

      actual = Integer(result[:output].to_s.strip, exception: false)
      return if actual == expected_tables

      raise "#{service.name} has #{actual.inspect} tables after the import, expected #{expected_tables}"
    end

    # Removes only what this restore created. The new service was never live
    # and only ever held a partial copy; the source is untouched.
    def fail!(restore, error)
      restore.reload
      service = restore.restored_service
      cleanup = []
      if service && !service.running?
        if restore.metadata["datastore_created"]
          destroyed = DokkuEngine.new(service.project.server).datastore_destroy(service)
          cleanup << "could not remove datastore #{service.dokku_app_name}: #{destroyed[:output]}" unless destroyed[:success]
        end
        service.destroy! if cleanup.empty?
      end
      message = [ error.message, *cleanup ].join("; ")
      restore.update!(status: "failed", completed_at: Time.current, log: message)
      ActivityEvent.create!(project: restore.project, service_name: restore.service_name, action: :warning,
        message: "Point-in-time recovery into #{restore.service_name} failed: #{message}",
        metadata: { "pitr_restore_id" => restore.id })
    rescue => cleanup_error
      Rails.logger.error("PitrRestoreJob cleanup for #{restore.id} failed: #{cleanup_error.message}")
      restore.update_columns(status: "failed", completed_at: Time.current, log: "#{error.message}; cleanup failed: #{cleanup_error.message}")
    end
end
