require "rails_helper"

RSpec.describe PitrRestoreJob do
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:source) { create(:service, :database, project: project, subtype: "postgres", name: "main-db", status: "running") }
  let(:restored) { create(:service, :database, project: project, subtype: "postgres", name: "main-db-copy", status: "deploying") }
  let(:base) { source.backups.create!(backup_kind: "pitr_base", status: "completed", created_at: 2.hours.ago) }
  let(:target) { 1.hour.ago.change(usec: 0) }
  let!(:restore) do
    PitrRestore.create!(source_service: source, restored_service: restored, backup: base, project: project,
      target_time: target, service_name: restored.name)
  end
  let(:engine) { instance_double(DokkuEngine) }
  let(:host) { instance_double(HostEngine) }
  let(:recovery) { instance_double(PostgresPhysicalRecovery) }
  let(:source_db) { described_class.database_name(source) }

  before do
    allow(DokkuEngine).to receive(:new).and_return(engine)
    allow(HostEngine).to receive(:new).and_return(host)
    allow_any_instance_of(BackupArtifactStore).to receive(:materialize).with(base).and_yield("/tmp/base.tar.gz")
    allow(PostgresPhysicalRecovery).to receive(:new).and_return(recovery)
    allow(recovery).to receive(:call).and_yield(recovery)
    allow(recovery).to receive(:database_exists?).with(source_db).and_return(true)
    allow(recovery).to receive(:table_count).with(source_db).and_return(4)
    allow(recovery).to receive(:dump_database).and_return(success: true)
    allow(engine).to receive(:datastore_create).and_return(success: true, output: "")
    allow(engine).to receive(:datastore_import_from).and_return(success: true, output: "")
    allow(engine).to receive(:datastore_destroy).and_return(success: true, output: "")
    allow(host).to receive(:run).and_return(success: true, output: "4\n")
  end

  it "recovers in isolation, loads the data into the new service and verifies it before reporting success" do
    described_class.perform_now(restore.id)

    expect(PostgresPhysicalRecovery).to have_received(:new).with(base, match(/\Araildock-pitr-#{restore.id}-/), target_time: target)
    expect(recovery).to have_received(:dump_database).with(source_db, kind_of(String))
    expect(engine).to have_received(:datastore_create).with(restored)
    expect(engine).to have_received(:datastore_import_from).with(restored, kind_of(String))
    expect(host).to have_received(:run).with(include("dokku.postgres.#{restored.dokku_app_name}", "pg_tables"))
    expect(restore.reload.status).to eq("succeeded")
    expect(restore.metadata["table_count"]).to eq(4)
    expect(restored.reload.status).to eq("running")
    expect(ActivityEvent.where(project: project, action: "created").pluck(:message).join).to include("Recovered main-db")
  end

  it "never writes to the source service" do
    described_class.perform_now(restore.id)

    expect(engine).not_to have_received(:datastore_create).with(source)
    expect(engine).not_to have_received(:datastore_import_from).with(source, anything)
    expect(engine).not_to have_received(:datastore_destroy)
    expect(source.reload.status).to eq("running")
  end

  it "fails, and removes only the new datastore and service, when the copy does not match" do
    allow(host).to receive(:run).and_return(success: true, output: "3\n")

    expect { described_class.perform_now(restore.id) }.to raise_error(/3 tables after the import, expected 4/)

    expect(restore.reload.status).to eq("failed")
    expect(restore.log).to include("expected 4")
    expect(engine).to have_received(:datastore_destroy).with(restored).once
    expect(Service.exists?(restored.id)).to be(false)
    expect(Service.exists?(source.id)).to be(true)
    expect(ActivityEvent.where(project: project, action: "warning").pluck(:message).join).to include("failed")
  end

  it "does not destroy a datastore it never created" do
    allow(recovery).to receive(:call).and_raise("recovery ended before configured recovery target was reached")

    expect { described_class.perform_now(restore.id) }.to raise_error(/recovery target/)

    expect(engine).not_to have_received(:datastore_create)
    expect(engine).not_to have_received(:datastore_destroy)
    expect(restore.reload).to have_attributes(status: "failed")
    expect(Service.exists?(restored.id)).to be(false)
  end

  it "keeps the new service record when the datastore cannot be removed" do
    allow(engine).to receive(:datastore_import_from).and_return(success: false, output: "pg_restore: error")
    allow(engine).to receive(:datastore_destroy).and_return(success: false, output: "ssh down")

    expect { described_class.perform_now(restore.id) }.to raise_error(/pg_restore/)

    expect(restore.reload.log).to include("could not remove datastore")
    expect(Service.exists?(restored.id)).to be(true)
  end

  it "refuses a cluster without the source database" do
    allow(recovery).to receive(:database_exists?).and_return(false)

    expect { described_class.perform_now(restore.id) }.to raise_error(/no database named/)
    expect(engine).not_to have_received(:datastore_create)
  end
end
