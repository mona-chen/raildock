require "rails_helper"

RSpec.describe BackupArtifactStore do
  let(:server) { create(:server) }
  let(:service) { create(:service, :database, project: create(:project, server: server), subtype: "postgres") }
  let(:destination) do
    server.backup_destinations.create!(name: "R2", provider: "r2", endpoint: "https://example.r2.cloudflarestorage.com",
      region: "auto", bucket: "backups", access_key_id: "key", secret_access_key: "secret")
  end
  let(:client) { instance_double(BackupDestinationClient) }

  before do
    allow(BackupDestinationClient).to receive(:new).with(destination).and_return(client)
  end

  it "encrypts before upload and verifies plaintext after download" do
    backup = service.backups.create!(status: "running", backup_destination: destination)
    uploaded = nil
    allow(client).to receive(:upload) { |path, _key| uploaded = File.binread(path) }
    allow(client).to receive(:download) { |_key, path| File.binwrite(path, uploaded) }

    Dir.mktmpdir do |dir|
      source = File.join(dir, "database.dump")
      File.binwrite(source, "database dump")
      described_class.new.persist!(backup, source)

      expect(backup.reload).to be_encrypted
      expect(uploaded).not_to include("database dump")
      described_class.new.materialize(backup) { |path| expect(File.binread(path)).to eq("database dump") }
    end
  end

  it "refuses a downloaded artifact that does not match its checksum" do
    backup = service.backups.create!(status: "completed", backup_destination: destination, storage_key: "backup.enc", encrypted: true,
      metadata: { "checksum" => Digest::SHA256.hexdigest("expected") })
    allow(client).to receive(:download) do |_key, path|
      plain = Tempfile.new
      File.binwrite(plain.path, "unexpected")
      BackupArtifactCipher.new.encrypt(plain.path, path, destination.encryption_key)
      plain.close!
    end

    expect { described_class.new.materialize(backup) { } }.to raise_error("Backup checksum verification failed")
  end
end
