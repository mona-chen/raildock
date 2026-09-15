require "rails_helper"

RSpec.describe DestructionSnapshot do
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:client) { instance_double(BackupDestinationClient) }

  def verified_destination(name: "s3")
    server.backup_destinations.create!(
      name: name,
      provider: "s3",
      region: "us-east-1",
      bucket: "raildock-backups",
      access_key_id: "key",
      secret_access_key: "secret",
      status: "verified",
      last_verified_at: Time.current
    )
  end

  before do
    allow(BackupDestinationClient).to receive(:new).and_return(client)
    allow(client).to receive(:upload) { |path, _key| { content_length: File.size(path) } }
  end

  describe ".data_bearing?" do
    it "is false for a stateless app and true for datastores and mounted volumes" do
      app = create(:service, project: project)
      database = create(:service, :database, project: project)
      create(:storage_mount, :volume, service: app)

      expect(described_class.data_bearing?(create(:service, project: project))).to be false
      expect(described_class.data_bearing?(database)).to be true
      expect(described_class.data_bearing?(app.reload)).to be true
    end
  end

  describe "#call" do
    it "skips services without persistent data" do
      service = create(:service, project: project)

      result = described_class.new(service).call

      expect(result).to be_success
      expect(result.backup).to be_nil
    end

    it "refuses when no verified destination exists" do
      service = create(:service, :database, project: project)

      result = described_class.new(service).call

      expect(result).not_to be_success
      expect(result.error).to match(/no verified backup destination/)
      expect(service.backups.count).to eq(0)
    end

    it "ignores destinations that have not been verified" do
      service = create(:service, :database, project: project)
      verified_destination.update!(status: "failed", last_error: "bad credentials")

      expect(described_class.new(service).call).not_to be_success
    end

    it "exports a datastore to a verified destination and marks the artifact verified" do
      verified_destination
      service = create(:service, :database, project: project)
      allow_any_instance_of(DokkuEngine).to receive(:datastore_export_to) do |_engine, _svc, path|
        File.binwrite(path, "production dump")
        { success: true, output: "" }
      end

      result = described_class.new(service).call

      expect(result).to be_success
      expect(result.backup).to be_completed
      expect(result.backup.remote_verified?).to be true
      expect(result.backup.metadata).to include("trigger" => "pre_destroy", "service_name" => service.name)
      expect(result.backup.metadata.dig("recreation", "subtype")).to eq("postgres")
      expect(ActivityEvent.where(service_name: service.name).last.message).to match(/Snapshot captured/)
    end

    it "snapshots mounted volumes too" do
      verified_destination
      service = create(:service, project: project)
      create(:storage_mount, :volume, service: service, container_path: "/var/data")
      allow_any_instance_of(HostEngine).to receive(:volume_export_to) do |_engine, _host_path, path|
        File.binwrite(path, "volume tar")
        { success: true, output: "" }
      end

      result = described_class.new(service).call

      expect(result).to be_success
      expect(service.backups.reload.map(&:backup_kind)).to eq(%w[volume])
      expect(result.backup.metadata.dig("recreation", "storage_mounts")).to include(
        hash_including("container" => "/var/data", "kind" => "volume")
      )
    end

    it "fails when the export itself fails and records the failure on the backup" do
      verified_destination
      service = create(:service, :database, project: project)
      allow_any_instance_of(DokkuEngine).to receive(:datastore_export_to).and_return({ success: false, output: "dokku exploded" })

      result = described_class.new(service).call

      expect(result).not_to be_success
      expect(result.error).to match(/dokku exploded/)
      expect(service.backups.last.status).to eq("failed")
    end

    it "fails when the upload cannot be verified" do
      verified_destination
      service = create(:service, :database, project: project)
      allow_any_instance_of(DokkuEngine).to receive(:datastore_export_to) do |_engine, _svc, path|
        File.binwrite(path, "dump")
        { success: true, output: "" }
      end
      allow(client).to receive(:upload).and_raise("uploaded object is 0 bytes on the destination, expected 4")

      result = described_class.new(service).call

      expect(result).not_to be_success
      expect(result.error).to match(/uploaded object is 0 bytes/)
    end
  end

  describe ".capture_all" do
    it "collects an error for every data-bearing service that could not be snapshotted" do
      database = create(:service, :database, project: project)
      create(:service, project: project)

      report = described_class.capture_all(project.services.to_a)

      expect(report[:errors].length).to eq(1)
      expect(report[:errors].first).to include(database.name)
    end
  end

  describe "trigger" do
    it "records a pre-restore snapshot distinctly from a pre-destroy one" do
      verified_destination
      service = create(:service, :database, project: project)
      allow_any_instance_of(DokkuEngine).to receive(:datastore_export_to) do |_engine, _svc, path|
        File.binwrite(path, "current production data")
        { success: true, output: "" }
      end

      result = described_class.new(service, trigger: "pre_restore").call

      expect(result).to be_success
      expect(result.backup.metadata["trigger"]).to eq("pre_restore")
      keys = result.backup.backup_copies.map(&:storage_key).compact
      expect(keys).to all(include("pre-restore/"))
      expect(keys).to be_present
      expect(ActivityEvent.where(service_name: service.name).last.message).to match(/before restoring over/)
    end

    it "falls back to the pre_destroy trigger for an unknown value" do
      verified_destination
      service = create(:service, :database, project: project)
      allow_any_instance_of(DokkuEngine).to receive(:datastore_export_to) do |_engine, _svc, path|
        File.binwrite(path, "current production data")
        { success: true, output: "" }
      end

      result = described_class.new(service, trigger: "something_else").call

      expect(result.backup.metadata["trigger"]).to eq("pre_destroy")
    end
  end
end
