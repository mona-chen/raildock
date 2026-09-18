require "rails_helper"

RSpec.describe PostgresBaseBackupJob, type: :job do
  # The reported bug: tar output on stdout cannot stream WAL, and `-X stream` is
  # pg_basebackup's default, so the command failed before writing a single byte
  # ("cannot stream write-ahead logs in tar mode to stdout").
  it "takes a tar base backup with the WAL method that stdout allows" do
    server = create(:server)
    destination = server.backup_destinations.create!(name: "S3", provider: "s3", region: "us-east-1",
      bucket: "recovery", access_key_id: "access", secret_access_key: "secret")
    service = create(:service, :database, project: create(:project, server: server))
    config = service.create_postgres_pitr_config!(backup_destination: destination, enabled: true,
      retention_days: 7, status: "active")

    commands = []
    allow_any_instance_of(HostEngine).to receive(:run_to_file) do |_, command, path|
      commands << command
      File.binwrite(path, "base backup")
      { success: true, output: "" }
    end
    allow_any_instance_of(BackupDestinationClient).to receive(:upload) { |_, _, key| key }

    described_class.perform_now(config.id)

    expect(commands.length).to eq(1)
    expect(commands.first).to include("-D - -Ft -z -X fetch")
    expect(commands.first).not_to include("-X stream")
    expect(config.reload.last_base_backup_at).to be_present
    expect(service.backups.last.status).to eq("completed")
  end

  it "records the failure on the config when the datastore refuses the backup" do
    server = create(:server)
    destination = server.backup_destinations.create!(name: "S3", provider: "s3", region: "us-east-1",
      bucket: "recovery", access_key_id: "access", secret_access_key: "secret")
    service = create(:service, :database, project: create(:project, server: server))
    config = service.create_postgres_pitr_config!(backup_destination: destination, enabled: true,
      retention_days: 7, status: "active")

    allow_any_instance_of(HostEngine).to receive(:run_to_file)
      .and_return({ success: false, output: "pg_basebackup: error: could not connect" })

    expect { described_class.perform_now(config.id) }.to raise_error(/pg_basebackup/)
    expect(config.reload).to be_error
    expect(config.last_error).to match(/could not connect/)
    expect(service.backups.last.status).to eq("failed")
  end
end
