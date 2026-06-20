require "rails_helper"

RSpec.describe "Service recovery", type: :request do
  let(:user) { create(:user) }
  let(:server) { create(:server) }
  let(:service) { create(:service, :database, project: create(:project, server: server), subtype: "postgres") }
  let(:headers) { auth_headers(user) }

  it "creates and verifies an encrypted off-site destination without returning credentials" do
    verifier = instance_double(BackupDestinationClient, verify!: true)
    allow(BackupDestinationClient).to receive(:new).and_return(verifier)

    post "/api/services/#{service.id}/recovery/destinations", headers: headers, params: {
      name: "Production R2", provider: "r2", endpoint: "https://account.r2.cloudflarestorage.com",
      region: "auto", bucket: "recovery", access_key_id: "access", secret_access_key: "secret"
    }, as: :json

    expect(response).to have_http_status(:created)
    body = response.parsed_body
    expect(body).to include("configured" => true, "recovery_key" => match(/\A[0-9a-f]{64}\z/))
    expect(body.to_json).not_to include("secret")
  end

  it "queues a volume snapshot to the selected destination" do
    mount = create(:storage_mount, service: service)
    destination = server.backup_destinations.create!(name: "S3", provider: "s3", region: "us-east-1", bucket: "recovery",
      access_key_id: "access", secret_access_key: "secret")
    allow(VolumeBackupJob).to receive(:perform_later)

    post "/api/services/#{service.id}/recovery/volumes/#{mount.id}/snapshot", headers: headers,
      params: { backup_destination_id: destination.id }, as: :json

    expect(response).to have_http_status(:accepted)
    backup = service.backups.last
    expect(backup).to be_backup_kind_volume
    expect(backup.backup_destination).to eq(destination)
    expect(VolumeBackupJob).to have_received(:perform_later).with(backup.id, mount.id)
  end

  it "enables PostgreSQL PITR and immediately queues a base backup" do
    destination = server.backup_destinations.create!(name: "S3", provider: "s3", region: "us-east-1", bucket: "recovery",
      access_key_id: "access", secret_access_key: "secret")
    allow_any_instance_of(PostgresPitrConfigurator).to receive(:enable!) do |configurator|
      configurator.instance_variable_get(:@config).update!(enabled: true, status: "active")
    end
    allow(PostgresBaseBackupJob).to receive(:perform_later)

    put "/api/services/#{service.id}/recovery/pitr", headers: headers,
      params: { backup_destination_id: destination.id, retention_days: 14 }, as: :json

    expect(response).to have_http_status(:ok)
    config = service.reload.postgres_pitr_config
    expect(config).to be_enabled
    expect(config.retention_days).to eq(14)
    expect(PostgresBaseBackupJob).to have_received(:perform_later).with(config.id)
  end
end
