require "rails_helper"

RSpec.describe "Service backups", type: :request do
  let(:user) { create(:user) }
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:service) { create(:service, :database, project: project, subtype: "postgres") }

  around do |example|
    Dir.mktmpdir do |dir|
      @path = File.join(dir, "verified.dump")
      File.binwrite(@path, "verified database dump")
      example.run
    end
  end

  let!(:backup) do
    service.backups.create!(
      status: "completed",
      file_path: @path,
      size: File.size(@path),
      metadata: { "checksum" => Digest::SHA256.file(@path).hexdigest, "verified_at" => Time.current.iso8601 }
    )
  end

  def verified_snapshot
    DestructionSnapshot::Result.new(success: true, backup: nil, destinations: [], error: nil)
  end

  it "downloads an available verified artifact" do
    get "/api/services/#{service.id}/backups/#{backup.id}/download", headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("verified database dump")
  end

  it "restores an available artifact through the datastore adapter" do
    allow_any_instance_of(DokkuEngine).to receive(:datastore_import_from).with(service, @path).and_return(success: true, output: "")
    allow_any_instance_of(DestructionSnapshot).to receive(:call).and_return(verified_snapshot)

    expect {
      post "/api/services/#{service.id}/backups/#{backup.id}/restore", params: { confirm: service.name }, headers: auth_headers(user)
    }.to change(ActivityEvent, :count).by(1)

    expect(response).to have_http_status(:ok)
  end

  it "requires typed confirmation before restoring over live data" do
    expect_any_instance_of(DokkuEngine).not_to receive(:datastore_import_from)

    post "/api/services/#{service.id}/backups/#{backup.id}/restore", headers: auth_headers(user)

    expect(response).to have_http_status(:precondition_required)
    expect(response.parsed_body["code"]).to eq("confirmation_required")
    expect(response.parsed_body["restore"]["snapshots_since"]).to eq(0)
  end

  it "captures a pre-restore snapshot so the restore itself is reversible" do
    allow_any_instance_of(DokkuEngine).to receive(:datastore_import_from).and_return(success: true, output: "")
    allow(DestructionSnapshot).to receive(:new).and_call_original
    expect(DestructionSnapshot).to receive(:new)
      .with(service, trigger: "pre_restore")
      .and_return(instance_double(DestructionSnapshot, call: verified_snapshot))

    post "/api/services/#{service.id}/backups/#{backup.id}/restore",
      params: { confirm: service.name }, headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
  end

  it "refuses to overwrite live data when no pre-restore snapshot can be taken" do
    failure = DestructionSnapshot::Result.new(
      success: false, backup: nil, destinations: [], error: "no verified backup destination is configured"
    )
    allow(DestructionSnapshot).to receive(:new).and_return(instance_double(DestructionSnapshot, call: failure))
    expect_any_instance_of(DokkuEngine).not_to receive(:datastore_import_from)

    post "/api/services/#{service.id}/backups/#{backup.id}/restore",
      params: { confirm: service.name }, headers: auth_headers(user)

    expect(response).to have_http_status(:precondition_required)
    expect(response.parsed_body["code"]).to eq("snapshot_required")
  end

  it "overwrites live data when the loss is explicitly acknowledged" do
    failure = DestructionSnapshot::Result.new(
      success: false, backup: nil, destinations: [], error: "no verified backup destination is configured"
    )
    allow(DestructionSnapshot).to receive(:new).and_return(instance_double(DestructionSnapshot, call: failure))
    allow_any_instance_of(DokkuEngine).to receive(:datastore_import_from).and_return(success: true, output: "")

    expect {
      post "/api/services/#{service.id}/backups/#{backup.id}/restore",
        params: { confirm: service.name, force_destroy_data: true }, headers: auth_headers(user)
    }.to change(ActivityEvent, :count).by(2)

    expect(response).to have_http_status(:ok)
    warning = ActivityEvent.where(action: :warning).last
    expect(warning.message).to include("without a pre-restore snapshot")
  end

  it "refuses to delete the last remaining backup without an explicit acknowledgement" do
    expect {
      delete "/api/services/#{service.id}/backups/#{backup.id}", headers: auth_headers(user)
    }.not_to change(Backup, :count)

    expect(response).to have_http_status(:precondition_required)
    expect(response.parsed_body["code"]).to eq("last_backup")
    expect(File).to exist(@path)
  end

  it "deletes the database record and artifact together once acknowledged" do
    expect {
      delete "/api/services/#{service.id}/backups/#{backup.id}", params: { force: true }, headers: auth_headers(user)
    }.to change(Backup, :count).by(-1)

    expect(response).to have_http_status(:no_content)
    expect(File).not_to exist(@path)
  end

  it "does not download a missing artifact" do
    File.delete(@path)

    get "/api/services/#{service.id}/backups/#{backup.id}/download", headers: auth_headers(user)

    expect(response).to have_http_status(:not_found)
  end

  it "restores a volume snapshot to its original mount" do
    volume_backup = service.backups.create!(status: "completed", backup_kind: "volume", file_path: @path,
      size: File.size(@path), metadata: { "checksum" => Digest::SHA256.file(@path).hexdigest, "host_path" => "uploads-data" })
    allow_any_instance_of(HostEngine).to receive(:volume_import_from).with("uploads-data", @path).and_return(success: true, output: "")
    allow_any_instance_of(DestructionSnapshot).to receive(:call).and_return(verified_snapshot)

    post "/api/services/#{service.id}/backups/#{volume_backup.id}/restore",
      params: { confirm: service.name }, headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
  end

  describe "GET /api/services/:id/snapshots" do
    it "lists only volume backups" do
      volume_backup = service.backups.create!(status: "completed", backup_kind: "volume", file_path: @path,
        size: File.size(@path), metadata: { "checksum" => Digest::SHA256.file(@path).hexdigest })
      service.backups.create!(status: "completed", backup_kind: "database", file_path: @path,
        size: File.size(@path), metadata: { "checksum" => Digest::SHA256.file(@path).hexdigest })

      get "/api/services/#{service.id}/snapshots", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body.map { |b| b["id"] }
      expect(ids).to include(volume_backup.id)
      expect(ids).not_to include(service.backups.find_by(backup_kind: "database").id)
    end
  end

  describe "POST /api/services/:id/create_backup_schedule" do
    it "creates a volume snapshot schedule" do
      mount = service.storage_mounts.create!(host_path: "app-data", container_path: "/data", kind: "volume")

      expect {
        post "/api/services/#{service.id}/create_backup_schedule", params: {
          backup_schedule: {
            frequency: "daily",
            retention_count: 3,
            backup_kind: "volume",
            storage_mount_id: mount.id,
            destination_ids: [ "dest-1" ]
          }
        }, headers: auth_headers(user)
      }.to change(BackupSchedule, :count).by(1)

      expect(response).to have_http_status(:created)
      schedule = BackupSchedule.last
      expect(schedule.backup_kind).to eq("volume")
      expect(schedule.storage_mount_id).to eq(mount.id)
      expect(schedule.destination_ids).to eq([ "dest-1" ])
      expect(schedule.next_run_at).to be_present
    end

    it "rejects a volume schedule without a storage mount" do
      post "/api/services/#{service.id}/create_backup_schedule", params: {
        backup_schedule: {
          frequency: "daily",
          retention_count: 3,
          backup_kind: "volume"
        }
      }, headers: auth_headers(user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("Storage mount is required for volume snapshots")
    end
  end
end
