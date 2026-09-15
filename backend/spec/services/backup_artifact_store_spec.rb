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

  it "writes to an organization destination instead of leaving a local-only copy" do
    organization = server.organization
    organization_destination = organization.backup_destinations.create!(
      name: "org-r2", provider: "r2", endpoint: "https://example.r2.cloudflarestorage.com",
      region: "auto", bucket: "org-backups", access_key_id: "key", secret_access_key: "secret",
      status: "verified", last_verified_at: Time.current
    )
    allow(BackupDestinationClient).to receive(:new).with(organization_destination).and_return(client)
    allow(client).to receive(:upload) { |path, _key| { content_length: File.size(path) } }

    backup = service.backups.create!(status: "running", metadata: { "destination_ids" => [ organization_destination.id.to_s ] })

    Dir.mktmpdir do |dir|
      source = File.join(dir, "database.dump")
      File.binwrite(source, "organization dump")
      described_class.new.persist!(backup, source, destination_ids: [ organization_destination.id.to_s ])

      expect(backup.reload.backup_copies.sole.backup_destination).to eq(organization_destination)
      expect(backup.metadata["remote_verified"]).to be(true)
      expect(backup.metadata["service_name"]).to eq(service.name)
      expect(File).not_to exist(source)
    end
  end

  it "raises when a requested destination does not exist instead of writing nothing" do
    backup = service.backups.create!(status: "running", metadata: { "destination_ids" => [ "999999" ] })

    Dir.mktmpdir do |dir|
      source = File.join(dir, "database.dump")
      File.binwrite(source, "organization dump")

      expect {
        described_class.new.persist!(backup, source, destination_ids: [ "999999" ])
      }.to raise_error(/Unknown backup destination/)
    end
  end

  it "never reports a completed backup that has no copy at all" do
    backup = service.backups.create!(status: "running")
    store = described_class.new
    allow(store).to receive(:resolve_destinations).and_return([])

    Dir.mktmpdir do |dir|
      source = File.join(dir, "database.dump")
      File.binwrite(source, "dump")

      expect {
        store.persist!(backup, source, destination_ids: [ "5" ])
      }.to raise_error(/no copies/)
      expect(backup.reload.status).not_to eq("completed")
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
