require "rails_helper"

RSpec.describe BackupJob, type: :job do
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:service) { create(:service, :database, project: project, subtype: "postgres") }
  let(:backup) { service.backups.create!(status: "pending") }

  around do |example|
    Dir.mktmpdir do |dir|
      previous = ENV["RAILDOCK_BACKUPS_DIR"]
      ENV["RAILDOCK_BACKUPS_DIR"] = dir
      example.run
    ensure
      ENV["RAILDOCK_BACKUPS_DIR"] = previous
    end
  end

  it "persists and verifies the exported artifact" do
    allow_any_instance_of(DokkuEngine).to receive(:datastore_export_to) do |_, _, path|
      File.binwrite(path, "database dump")
      { success: true, output: "" }
    end

    expect { described_class.perform_now(backup.id) }.to change(ActivityEvent, :count).by(1)

    backup.reload
    expect(backup.status).to eq("completed")
    expect(backup).to be_available
    expect(backup.metadata["checksum"]).to eq(Digest::SHA256.hexdigest("database dump"))
    expect(backup.metadata["verified_at"]).to be_present
  end

  it "records a failure and removes no successful state" do
    allow_any_instance_of(DokkuEngine).to receive(:datastore_export_to).and_return(success: false, output: "export failed")

    expect { described_class.perform_now(backup.id) }.to raise_error("export failed")
    expect(backup.reload.status).to eq("failed")
    expect(backup.file_path).to be_blank
  end
end
