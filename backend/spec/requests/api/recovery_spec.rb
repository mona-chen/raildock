require "rails_helper"

RSpec.describe "Service recovery", type: :request do
  let(:user) { create(:user, :admin) }
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

  it "refuses an unverified destination for PITR, since WAL ships unattended" do
    destination = server.backup_destinations.create!(name: "S3", provider: "s3", region: "us-east-1", bucket: "recovery",
      access_key_id: "access", secret_access_key: "secret")
    expect_any_instance_of(PostgresPitrConfigurator).not_to receive(:enable!)

    put "/api/services/#{service.id}/recovery/pitr", headers: headers,
      params: { backup_destination_id: destination.id, retention_days: 14 }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("destination_unverified")
  end

  it "keeps the configured retention when only the destination changes" do
    destination = server.backup_destinations.create!(name: "S3", provider: "s3", region: "us-east-1", bucket: "recovery",
      access_key_id: "access", secret_access_key: "secret", status: "verified")
    service.create_postgres_pitr_config!(backup_destination: destination, retention_days: 30)
    allow_any_instance_of(PostgresPitrConfigurator).to receive(:enable!)
    allow(PostgresBaseBackupJob).to receive(:perform_later)

    put "/api/services/#{service.id}/recovery/pitr", headers: headers, params: { backup_destination_id: destination.id }, as: :json

    expect(response).to have_http_status(:ok)
    expect(service.reload.postgres_pitr_config.retention_days).to eq(30)
  end

  # Enabling archiving restarts PostgreSQL; changing the window must not.
  it "changes the retention window of running PITR without restarting PostgreSQL" do
    destination = server.backup_destinations.create!(name: "S3", provider: "s3", region: "us-east-1", bucket: "recovery",
      access_key_id: "access", secret_access_key: "secret", status: "verified")
    service.create_postgres_pitr_config!(backup_destination: destination, retention_days: 7, enabled: true, status: "active")
    expect_any_instance_of(PostgresPitrConfigurator).not_to receive(:enable!)
    expect(PostgresBaseBackupJob).not_to receive(:perform_later)

    put "/api/services/#{service.id}/recovery/pitr", headers: headers,
      params: { backup_destination_id: destination.id, retention_days: 30 }, as: :json

    expect(response).to have_http_status(:ok)
    expect(service.reload.postgres_pitr_config.retention_days).to eq(30)
  end

  it "starts a fresh base backup when running PITR moves to another destination" do
    first = server.backup_destinations.create!(name: "S3", provider: "s3", region: "us-east-1", bucket: "a",
      access_key_id: "access", secret_access_key: "secret", status: "verified")
    second = server.backup_destinations.create!(name: "R2", provider: "r2", region: "auto", bucket: "b",
      endpoint: "https://acct.r2.cloudflarestorage.com", access_key_id: "access", secret_access_key: "secret", status: "verified")
    config = service.create_postgres_pitr_config!(backup_destination: first, retention_days: 7, enabled: true, status: "active")
    expect_any_instance_of(PostgresPitrConfigurator).not_to receive(:enable!)
    allow(PostgresBaseBackupJob).to receive(:perform_later)

    put "/api/services/#{service.id}/recovery/pitr", headers: headers, params: { backup_destination_id: second.id }, as: :json

    expect(response).to have_http_status(:ok)
    expect(PostgresBaseBackupJob).to have_received(:perform_later).with(config.id)
  end

  it "snapshots a volume to the service's default destinations when none are given" do
    mount = create(:storage_mount, service: service)
    destination = server.backup_destinations.create!(name: "S3", provider: "s3", region: "us-east-1", bucket: "recovery",
      access_key_id: "access", secret_access_key: "secret")
    service.update!(default_backup_destination_ids: [ destination.id ])
    allow(VolumeBackupJob).to receive(:perform_later)

    post "/api/services/#{service.id}/recovery/volumes/#{mount.id}/snapshot", headers: headers, as: :json

    expect(response).to have_http_status(:accepted)
    expect(service.backups.last.metadata["destination_ids"]).to eq([ destination.id.to_s ])
  end

  it "refuses a volume snapshot to a destination the service cannot reach" do
    mount = create(:storage_mount, service: service)
    foreign = create(:server).backup_destinations.create!(name: "Elsewhere", provider: "s3", region: "us-east-1", bucket: "other",
      access_key_id: "access", secret_access_key: "secret")
    expect(VolumeBackupJob).not_to receive(:perform_later)

    post "/api/services/#{service.id}/recovery/volumes/#{mount.id}/snapshot", headers: headers,
      params: { backup_destination_ids: [ foreign.id ] }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "does not let a service remove an organization-wide destination" do
    organization = create(:organization)
    service.project.update!(organization: organization)
    shared = organization.backup_destinations.create!(name: "Shared", provider: "s3", region: "us-east-1", bucket: "shared",
      access_key_id: "access", secret_access_key: "secret")

    delete "/api/services/#{service.id}/recovery/destinations/#{shared.id}", headers: headers

    expect(response).to have_http_status(:forbidden)
    expect(BackupDestination.exists?(shared.id)).to be(true)
  end

  it "does not keep a destination whose verification failed when created from a service" do
    verifier = instance_double(BackupDestinationClient)
    allow(verifier).to receive(:verify!).and_raise("AccessDenied")
    allow(BackupDestinationClient).to receive(:new).and_return(verifier)

    expect {
      post "/api/services/#{service.id}/recovery/destinations", headers: headers,
        params: { name: "S3", provider: "s3", region: "us-east-1", bucket: "recovery", access_key_id: "a", secret_access_key: "s" }, as: :json
    }.not_to change(BackupDestination, :count)

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "enables PostgreSQL PITR and immediately queues a base backup" do
    destination = server.backup_destinations.create!(name: "S3", provider: "s3", region: "us-east-1", bucket: "recovery",
      access_key_id: "access", secret_access_key: "secret", status: "verified")
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

    # The reported bug: the picker was React state only, so every reload put it
    # back on "Local only".
    it "remembers the destinations picked for a service" do
      patch "/api/services/#{service.id}/recovery/preferences", headers: headers,
        params: { backup_destination_ids: [ destination.id ] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["backup_preferences"]["default_destination_ids"]).to eq([ destination.id.to_s ])
      expect(service.reload.default_backup_destination_ids).to eq([ destination.id.to_s ])

      get "/api/services/#{service.id}/recovery", headers: headers

      preferences = response.parsed_body["backup_preferences"]
      expect(preferences["service_destination_ids"]).to eq([ destination.id.to_s ])
      expect(preferences["default_destination_ids"]).to eq([ destination.id.to_s ])
    end

    it "inherits the organization default until the service picks its own" do
      organization.update!(default_backup_destination_ids: [ destination.id ])

      get "/api/services/#{service.id}/recovery", headers: headers

      preferences = response.parsed_body["backup_preferences"]
      expect(preferences["service_destination_ids"]).to be_nil
      expect(preferences["organization_destination_ids"]).to eq([ destination.id.to_s ])
      expect(preferences["default_destination_ids"]).to eq([ destination.id.to_s ])
    end

    it "treats an empty selection as a deliberate local-only choice" do
      organization.update!(default_backup_destination_ids: [ destination.id ])

      patch "/api/services/#{service.id}/recovery/preferences", headers: headers,
        params: { backup_destination_ids: [] }, as: :json

      expect(service.reload.default_backup_destination_ids).to eq([])
      expect(service.resolved_backup_destination_ids).to eq([])
    end

    it "clears the service choice so it inherits the organization default again" do
      organization.update!(default_backup_destination_ids: [ destination.id ])
      service.update!(default_backup_destination_ids: [])

      patch "/api/services/#{service.id}/recovery/preferences", headers: headers,
        params: { backup_destination_ids: nil }, as: :json

      expect(service.reload.default_backup_destination_ids).to be_nil
      expect(service.resolved_backup_destination_ids).to eq([ destination.id.to_s ])
    end

    it "drops a deleted destination from the service's remembered choice" do
      service.update!(default_backup_destination_ids: [ destination.id ])

      delete "/api/organizations/#{organization.id}/backup-destinations/#{destination.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(service.reload.default_backup_destination_ids).to eq([])
    end
  end
end
