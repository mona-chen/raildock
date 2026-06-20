require "rails_helper"

RSpec.describe VolumeBackupJob, type: :job do
  it "creates a verified snapshot for a named Docker volume" do
    server = create(:server)
    service = create(:service, project: create(:project, server: server))
    mount = create(:storage_mount, service: service, host_path: "uploads-data", container_path: "/app/uploads")
    backup = service.backups.create!(status: "pending", backup_kind: "volume")

    allow_any_instance_of(HostEngine).to receive(:volume_export_to) do |_, host_path, path|
      expect(host_path).to eq("uploads-data")
      File.binwrite(path, "compressed volume")
      { success: true, output: "" }
    end

    described_class.perform_now(backup.id, mount.id)
    expect(backup.reload.status).to eq("completed")
    expect(backup.metadata).to include("host_path" => "uploads-data", "checksum" => Digest::SHA256.hexdigest("compressed volume"))
  end
end
