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
      params: { backup_destination_ids: [ destination.id ] }, as: :json

    expect(response).to have_http_status(:accepted)
    backup = service.backups.last
    expect(backup).to be_backup_kind_volume
    expect(backup.metadata["destination_ids"]).to eq([ destination.id.to_s ])
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

  # The reported bug: a destination created in Settings belongs to the
  # organization, while a server is shared and usually has no organization of
  # its own. Reading `server.organization` hid every such destination, so the
  # service's Backup tab claimed nothing was configured right after one was
  # added.
  describe "off-site destinations owned by the project's organization" do
    let(:organization) { create(:organization) }
    let(:server) { create(:server, organization: nil) }
    let(:project) { create(:project, server: server, organization: organization) }
    let(:service) { create(:service, :database, project: project, subtype: "postgres") }
    let!(:destination) do
      organization.backup_destinations.create!(
        name: "Tween S3 Backup", provider: "s3", endpoint: "https://fs.tween.im",
        region: "us-east-1", bucket: "tween-backups",
        access_key_id: "access", secret_access_key: "secret"
      )
    end

    before { create(:organization_membership, user: user, organization: organization, role: :owner) }

    it "lists them even when the server has no organization" do
      expect(server.organization_id).to be_nil

      get "/api/services/#{service.id}/recovery", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["destinations"].map { |d| d["name"] }).to eq([ "Tween S3 Backup" ])
    end

    it "accepts one when a backup is requested" do
      allow(BackupJob).to receive(:perform_later)

      post "/api/services/#{service.id}/backup", headers: headers,
        params: { backup_destination_ids: [ destination.id ] }, as: :json

      expect(response).to have_http_status(:accepted)
      expect(service.backups.last.metadata["destination_ids"]).to eq([ destination.id.to_s ])
    end

    it "still refuses a destination owned by another organization" do
      other = create(:organization).backup_destinations.create!(
        name: "Someone Else", provider: "s3", region: "us-east-1", bucket: "theirs",
        access_key_id: "access", secret_access_key: "secret"
      )

      post "/api/services/#{service.id}/backup", headers: headers,
        params: { backup_destination_ids: [ other.id ] }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
