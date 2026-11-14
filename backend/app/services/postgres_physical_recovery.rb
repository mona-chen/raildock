require "shellwords"

# Restores into a private disposable volume/container. Never touches the live
# database or publishes a port. A drill succeeds only after PostgreSQL replays
# the archive, promotes, and answers a query outside recovery.
class PostgresPhysicalRecovery
  def initialize(backup, resource_name, target_time: nil)
    @backup = backup
    raise "Invalid drill resource name" unless resource_name.match?(/\Araildock-drill-[a-zA-Z0-9-]+\z/)
    @name = resource_name
    @target_time = target_time
    @host = HostEngine.new(backup.service.project.server)
  end

  def call(path)
    check!(@host.volume_import_from(@name, path))
    version = check!(@host.run("docker run --rm --network none -v #{q(@name)}:/data:ro alpine:3.20 cat /data/PG_VERSION"))[:output].strip
    raise "Unsupported PostgreSQL base backup version" unless version.match?(/\A(?:1[0-9]|[2-9][0-9])\z/)
    if @target_time && @target_time <= @backup.created_at
      raise "Recovery target must be later than the base backup"
    end

    setup = "mkdir -p /data/raildock_recovery_wal && rm -f /data/standby.signal && touch /data/recovery.signal"
    check!(@host.run("docker run --rm --network none -v #{q(@name)}:/data alpine:3.20 sh -c #{q(setup)}"))
    wal_backups.each do |wal|
      name = wal.metadata["wal_name"].to_s
      raise "Invalid archived WAL filename" unless PostgresWalArchiveJob::WAL_NAME.match?(name)
      BackupArtifactStore.new.materialize(wal) do |wal_path|
        write = "cat > /data/raildock_recovery_wal/#{name}"
        check!(@host.run_with_file("docker run --rm -i --network none -v #{q(@name)}:/data alpine:3.20 sh -c #{q(write)}", wal_path))
      end
    end

    command = "docker run -d --name #{q(@name)} --network none -v #{q(@name)}:/var/lib/postgresql/data " \
      "-e PGDATA=/var/lib/postgresql/data postgres:#{version} postgres -D /var/lib/postgresql/data -c archive_mode=off " \
      "-c listen_addresses='' -c unix_socket_directories=/tmp " \
      "-c #{q('restore_command=cp /var/lib/postgresql/data/raildock_recovery_wal/%f %p')} " \
      "-c recovery_target_timeline=latest -c recovery_target_action=promote"
    command += " -c #{q("recovery_target_time=#{@target_time.utc.iso8601}")}" if @target_time
    check!(@host.run(command))
    verification = "NOT pg_is_in_recovery()"
    if !@target_time && (latest = wal_backups.select { |wal| wal.metadata["wal_name"].to_s.match?(/\A[0-9A-F]{24}\z/) }.max_by { |wal| wal.metadata["wal_name"] })
      segment_size = latest.size.to_i
      unless segment_size.between?(1.megabyte, 1.gigabyte) && (segment_size & (segment_size - 1)).zero?
        raise "Archived WAL segment size is invalid"
      end
      filename = latest.metadata["wal_name"]
      lsn = "#{filename[8, 8].to_i(16).to_s(16)}/#{(filename[16, 8].to_i(16) * segment_size).to_s(16)}"
      verification = "(NOT pg_is_in_recovery()) AND COALESCE(pg_last_wal_replay_lsn() >= '#{lsn}'::pg_lsn, false)"
    end
    query = "docker exec #{q(@name)} psql -h /tmp -U postgres -d postgres -Atqc #{q("SELECT #{verification}")}"
    # Bound startup/replay time. A failed or unreachable target is a failed drill.
    wait = "for attempt in $(seq 1 120); do result=$(#{query} 2>/dev/null) && [ \"$result\" = t ] && exit 0; sleep 1; done; docker logs --tail 40 #{q(@name)}; exit 1"
    check!(@host.run("sh -c #{q(wait)}"))
    { recovered_at: @target_time&.iso8601, wal_count: wal_backups.count }
  ensure
    @host.run("docker rm -f #{q(@name)} >/dev/null 2>&1; docker volume rm #{q(@name)}")
  end

  private

  def wal_backups
    @wal_backups ||= @backup.service.backups.completed.where(backup_kind: "wal")
      .where("created_at >= ? OR metadata->>'wal_name' LIKE '%.history'", @backup.created_at).order(:created_at, :id).to_a
  end

  def q(value)
    Shellwords.escape(value.to_s)
  end

  def check!(result)
    raise result[:output].presence || "Isolated PostgreSQL recovery failed" unless result[:success]
    result
  end
end
