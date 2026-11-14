require "rails_helper"

RSpec.describe PostgresPhysicalRecovery do
  let(:service) { create(:service, :database) }
  let!(:backup) { service.backups.create!(backup_kind: "pitr_base", status: "completed") }
  let(:host) { instance_double(HostEngine) }
  let(:name) { "raildock-drill-test" }
  before do
    allow(HostEngine).to receive(:new).and_return(host)
    allow(host).to receive(:volume_import_from).and_return(success: true)
    allow(host).to receive(:run).and_return(success: true, output: "")
    allow(host).to receive(:run).with(/cat \/data\/PG_VERSION/).and_return(success: true, output: "16\n")
  end

  it "boots an isolated database and requires a query outside recovery" do
    described_class.new(backup, name).call("/tmp/base.tar.gz")
    expect(host).to have_received(:run).with(include("--network none", "postgres:16 postgres", "recovery_target_action=promote"))
    expect(host).to have_received(:run).with(include("SELECT", "pg_is_in_recovery"))
    expect(host).to have_received(:run).with(include("docker rm -f", "docker volume rm"))
  end

  it "fails and cleans up when PostgreSQL cannot reach the recovery target" do
    allow(host).to receive(:run).with(/for.*attempt/).and_return(success: false, output: "recovery ended before target")
    expect { described_class.new(backup, name, target_time: 1.minute.from_now).call("/tmp/base.tar.gz") }.to raise_error(/before target/)
    expect(host).to have_received(:run).with(include("docker volume rm"))
  end

  it "verifies each WAL artifact before copying it into the recovery archive" do
    wal = service.backups.create!(backup_kind: "wal", status: "completed", size: 16.megabytes, metadata: { "wal_name" => "000000010000000000000002" })
    allow_any_instance_of(BackupArtifactStore).to receive(:materialize).with(wal).and_yield("/tmp/wal")
    allow(host).to receive(:run_with_file).and_return(success: true)
    described_class.new(backup, name).call("/tmp/base.tar.gz")
    expect(host).to have_received(:run_with_file).with(include(wal.metadata["wal_name"]), "/tmp/wal")
  end
end
