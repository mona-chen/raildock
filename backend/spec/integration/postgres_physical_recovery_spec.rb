require "rails_helper"
require "open3"
require "tmpdir"

# Opt-in because it starts disposable Docker containers. CI runs this on Linux.
RSpec.describe "Physical PostgreSQL recovery", type: :integration do
  it "replays an archived transaction created after the base backup" do
    skip "Set RAILDOCK_RECOVERY_INTEGRATION=1 on a Docker host" unless ENV["RAILDOCK_RECOVERY_INTEGRATION"] == "1"
    source = "raildock-recovery-source-#{SecureRandom.hex(5)}"
    restored = "raildock-drill-#{SecureRandom.hex(5)}"
    shell = lambda do |command|
      output, error, status = Open3.capture3(command)
      raise "#{command}: #{error} #{output}" unless status.success?
      output
    end
    service = create(:service, :database)
    host_class = Class.new(HostEngine) do
      attr_reader :verified_count
      define_method(:initialize) { |resource| @resource = resource }
      define_method(:run) do |command|
        output, error, status = Open3.capture3(command)
        if status.success? && command.match?(/for.*attempt/)
          count, = Open3.capture3("docker", "exec", @resource, "psql", "-h", "/tmp", "-U", "postgres", "-Atqc", "SELECT count(*) FROM recovery_marker")
          @verified_count = count.strip.to_i
        end
        { success: status.success?, output: output + error }
      end
      define_method(:run_with_file) do |command, path|
        # Docker receives gzipped/WAL bytes; keep the pipe binary so Ruby does
        # not transcode invalid UTF-8 and abort the drill before it starts.
        output, error, status = Open3.capture3(command, stdin_data: File.binread(path), binmode: true)
        { success: status.success?, output: output + error }
      end
    end
    host = host_class.new(restored)
    allow(HostEngine).to receive(:new).and_return(host)

    Dir.mktmpdir("raildock-recovery-test") do |directory|
      shell.call("docker run -d --name #{source} --network none -e POSTGRES_HOST_AUTH_METHOD=trust postgres:16 postgres -c archive_mode=on -c wal_level=replica -c 'archive_command=cp %p /var/lib/postgresql/data/test_archive/%f'")
      shell.call("for attempt in $(seq 1 60); do docker exec #{source} pg_isready -U postgres >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1")
      shell.call("docker exec #{source} sh -c 'mkdir -p /var/lib/postgresql/data/test_archive && chown postgres:postgres /var/lib/postgresql/data/test_archive'")
      shell.call("docker exec #{source} psql -U postgres -c 'CREATE TABLE recovery_marker (id integer); INSERT INTO recovery_marker VALUES (1)'")
      base = service.backups.create!(backup_kind: "pitr_base", status: "completed")
      base_path = File.join(directory, "base.tar.gz")
      shell.call("docker exec #{source} pg_basebackup -U postgres -D - -Ft -z -X fetch > #{Shellwords.escape(base_path)}")
      segment = shell.call("docker exec #{source} psql -U postgres -Atqc 'SELECT pg_walfile_name(pg_current_wal_lsn())'").strip
      raise "Invalid test WAL segment" unless segment.match?(/\A[0-9A-F]{24}\z/)
      shell.call("docker exec #{source} psql -U postgres -c 'INSERT INTO recovery_marker VALUES (2)' -c 'SELECT pg_switch_wal()'")
      shell.call("for attempt in $(seq 1 60); do docker exec #{source} test -f /var/lib/postgresql/data/test_archive/#{segment} && exit 0; sleep 1; done; exit 1")
      names = shell.call("docker exec #{source} ls /var/lib/postgresql/data/test_archive").lines.map(&:strip).grep(PostgresWalArchiveJob::WAL_NAME)
      expect(names).not_to be_empty
      names.each do |name|
        wal_path = File.join(directory, name)
        shell.call("docker cp #{source}:/var/lib/postgresql/data/test_archive/#{name} #{Shellwords.escape(wal_path)}")
        wal = service.backups.create!(backup_kind: "wal", status: "completed", size: File.size(wal_path), metadata: { "wal_name" => name })
        allow_any_instance_of(BackupArtifactStore).to receive(:materialize).with(wal).and_yield(wal_path)
      end
      PostgresPhysicalRecovery.new(base, restored).call(base_path)
      expect(host.verified_count).to eq(2)
      expect(shell.call("docker ps -a --filter name=^/#{restored}$ --format '{{.Names}}'")).to be_empty
    end
  ensure
    Open3.capture3("docker rm -fv #{source}") if source
  end
end
