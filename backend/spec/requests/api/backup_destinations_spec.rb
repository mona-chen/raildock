require "rails_helper"

RSpec.describe "Organization backup destinations", type: :request do
  let(:user) { create(:user, :admin) }
  let(:organization) { create(:organization, owner: user) }
  let(:headers) { auth_headers(user).merge("X-Organization-ID" => organization.id.to_s) }

  before do
    create(:organization_membership, user: user, organization: organization, role: :owner)
  end

  it "lists organization destinations" do
    destination = organization.backup_destinations.create!(
      name: "S3", provider: "s3", region: "us-east-1", bucket: "backups",
      access_key_id: "access", secret_access_key: "secret"
    )

    get "/api/organizations/#{organization.id}/backup-destinations", headers: headers

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.length).to eq(1)
    expect(body.first).to include("name" => "S3", "bucket" => "backups")
    expect(body.first).not_to include("secret_access_key")
  end

  it "creates and verifies a destination" do
    verifier = instance_double(BackupDestinationClient, probe!: true)
    allow(BackupDestinationClient).to receive(:new).and_return(verifier)

    post "/api/organizations/#{organization.id}/backup-destinations", headers: headers, params: {
      name: "R2", provider: "r2", endpoint: "https://r2.example.com",
      region: "auto", bucket: "backups", access_key_id: "access", secret_access_key: "secret"
    }, as: :json

    expect(response).to have_http_status(:created)
    body = response.parsed_body
    expect(body).to include("name" => "R2", "configured" => true)
    expect(body["recovery_key"]).to match(/\A[0-9a-f]{64}\z/)
    expect(body).to include("status" => "verified")
    expect(organization.backup_destinations.count).to eq(1)
    expect(BackupDestinationClient).to have_received(:new).with(kind_of(BackupDestination), interactive: true)
  end

  let(:create_params) do
    {
      name: "R2", provider: "r2", endpoint: "https://acct.r2.cloudflarestorage.com", region: "auto",
      bucket: "backups", access_key_id: "access", secret_access_key: "secret"
    }
  end

  it "returns an error when verification fails" do
    allow_any_instance_of(BackupDestinationClient).to receive(:probe!).and_raise("Invalid credentials")

    post "/api/organizations/#{organization.id}/backup-destinations", headers: headers, params: create_params, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include("error" => /verification failed/i)
    expect(response.parsed_body).not_to have_key("recovery_key")
  end

  # The reported bug: a failed probe saved a "failed" row whose recovery key
  # was never shown, and retrying the same name hit the uniqueness check.
  it "leaves no row behind when verification fails, so the same name can be retried" do
    allow_any_instance_of(BackupDestinationClient).to receive(:probe!).and_raise("Invalid credentials")

    expect {
      post "/api/organizations/#{organization.id}/backup-destinations", headers: headers, params: create_params, as: :json
    }.not_to change(BackupDestination, :count)

    allow_any_instance_of(BackupDestinationClient).to receive(:probe!).and_return(true)
    post "/api/organizations/#{organization.id}/backup-destinations", headers: headers, params: create_params, as: :json

    expect(response).to have_http_status(:created)
    expect(organization.backup_destinations.pluck(:name)).to eq([ "R2" ])
  end

  it "accepts an operator-supplied recovery key without echoing it back" do
    allow_any_instance_of(BackupDestinationClient).to receive(:probe!).and_return(true)
    key = SecureRandom.hex(32)

    post "/api/organizations/#{organization.id}/backup-destinations", headers: headers,
      params: create_params.merge(encryption_key: key), as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).not_to have_key("recovery_key")
    expect(organization.backup_destinations.last.encryption_key).to eq(key)
  end

  it "rejects a malformed recovery key before contacting the bucket" do
    expect(BackupDestinationClient).not_to receive(:new)

    post "/api/organizations/#{organization.id}/backup-destinations", headers: headers,
      params: create_params.merge(encryption_key: "not-hex"), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error"]).to match(/recovery key/)
  end

  it "accepts S3-compatible provider presets" do
    allow_any_instance_of(BackupDestinationClient).to receive(:probe!).and_return(true)

    post "/api/organizations/#{organization.id}/backup-destinations", headers: headers, params: {
      name: "B2", provider: "b2", region: "us-west-004", bucket: "backups",
      access_key_id: "access", secret_access_key: "secret"
    }, as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include("provider" => "b2")
  end

  describe "editing a destination" do
    let!(:destination) do
      organization.backup_destinations.create!(
        name: "S3", provider: "s3", region: "us-east-1", bucket: "backups",
        access_key_id: "access", secret_access_key: "secret", status: "verified", last_verified_at: 1.day.ago
      )
    end
    let(:path) { "/api/organizations/#{organization.id}/backup-destinations/#{destination.id}" }

    it "leaves a working destination untouched when the new credentials fail" do
      allow_any_instance_of(BackupDestinationClient).to receive(:probe!).and_raise("SignatureDoesNotMatch")

      patch path, headers: headers, params: { access_key_id: "new", secret_access_key: "wrong" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      destination.reload
      expect(destination).to be_verified
      expect(destination.access_key_id).to eq("access")
      expect(destination.secret_access_key).to eq("secret")
      expect(destination.last_error).to be_nil
    end

    it "saves rotated credentials once they verify" do
      allow_any_instance_of(BackupDestinationClient).to receive(:probe!).and_return(true)

      patch path, headers: headers, params: { access_key_id: "new", secret_access_key: "rotated" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(destination.reload.secret_access_key).to eq("rotated")
      expect(destination.last_verified_at).to be > 1.minute.ago
    end

    it "keeps stored secrets when the fields are left blank" do
      allow_any_instance_of(BackupDestinationClient).to receive(:probe!).and_return(true)

      patch path, headers: headers, params: { bucket: "other", access_key_id: "", secret_access_key: "" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(destination.reload.bucket).to eq("other")
      expect(destination.access_key_id).to eq("access")
      expect(destination.secret_access_key).to eq("secret")
    end

    it "renames without probing the bucket" do
      expect(BackupDestinationClient).not_to receive(:new)

      # The edit form resubmits every field, blank endpoint included.
      patch path, headers: headers, params: { name: "Renamed", provider: "s3", endpoint: "", region: "us-east-1", bucket: "backups", access_key_id: "", secret_access_key: "" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(destination.reload.name).to eq("Renamed")
    end

    it "never changes the recovery key" do
      original = destination.encryption_key

      patch path, headers: headers, params: { name: "Renamed", encryption_key: SecureRandom.hex(32) }, as: :json

      expect(destination.reload.encryption_key).to eq(original)
    end
  end

  describe "verifying a destination" do
    let!(:destination) do
      organization.backup_destinations.create!(
        name: "S3", provider: "s3", region: "us-east-1", bucket: "backups",
        access_key_id: "access", secret_access_key: "secret", status: "verified", last_verified_at: 1.day.ago
      )
    end
    let(:path) { "/api/organizations/#{organization.id}/backup-destinations/#{destination.id}/verify" }

    it "records the failure reason on the stored destination" do
      allow_any_instance_of(BackupDestinationClient).to receive(:probe!).and_raise("bucket gone")

      post path, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(destination.reload).to be_failed
      expect(destination.last_error).to eq("bucket gone")
    end

    it "forbids regular members, because verification writes to the bucket" do
      member = create(:user, :admin)
      create(:organization_membership, user: member, organization: organization, role: :member)
      member_headers = auth_headers(member).merge("X-Organization-ID" => organization.id.to_s)
      expect(BackupDestinationClient).not_to receive(:new)

      post path, headers: member_headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  it "explains why a destination that still holds backups cannot be deleted" do
    destination = organization.backup_destinations.create!(
      name: "S3", provider: "s3", region: "us-east-1", bucket: "backups",
      access_key_id: "access", secret_access_key: "secret"
    )
    allow_any_instance_of(BackupDestination).to receive(:destroy).and_return(false)
    allow_any_instance_of(BackupDestination).to receive(:backups).and_return(double(count: 2))

    delete "/api/organizations/#{organization.id}/backup-destinations/#{destination.id}", headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include("code" => "destination_in_use")
    expect(response.parsed_body["error"]).to include("still holds 2 backups")
    expect(organization.backup_destinations.count).to eq(1)
  end

  it "allows admins to delete a destination" do
    destination = organization.backup_destinations.create!(
      name: "S3", provider: "s3", region: "us-east-1", bucket: "backups",
      access_key_id: "access", secret_access_key: "secret"
    )

    delete "/api/organizations/#{organization.id}/backup-destinations/#{destination.id}", headers: headers

    expect(response).to have_http_status(:no_content)
    expect(organization.backup_destinations.count).to eq(0)
  end

  it "forbids non-members from listing destinations" do
    other_user = create(:user, :admin)
    other_headers = auth_headers(other_user)

    get "/api/organizations/#{organization.id}/backup-destinations", headers: other_headers

    expect(response).to have_http_status(:forbidden)
  end

  it "forbids regular members from creating destinations" do
    member = create(:user, :admin)
    create(:organization_membership, user: member, organization: organization, role: :member)
    member_headers = auth_headers(member).merge("X-Organization-ID" => organization.id.to_s)

    post "/api/organizations/#{organization.id}/backup-destinations", headers: member_headers, params: {
      name: "S3", provider: "s3", region: "us-east-1", bucket: "backups",
      access_key_id: "access", secret_access_key: "secret"
    }, as: :json

    expect(response).to have_http_status(:forbidden)
  end

  describe "organization default destinations" do
    let!(:destination) do
      organization.backup_destinations.create!(
        name: "S3", provider: "s3", region: "us-east-1", bucket: "backups",
        access_key_id: "access", secret_access_key: "secret"
      )
    end

    it "stores the default that every service inherits" do
      patch "/api/organizations/#{organization.id}/backup-destinations/defaults", headers: headers,
        params: { destination_ids: [ destination.id ] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["default_destination_ids"]).to eq([ destination.id.to_s ])

      get "/api/organizations/#{organization.id}/backup-destinations/defaults", headers: headers
      expect(response.parsed_body["default_destination_ids"]).to eq([ destination.id.to_s ])
    end

    it "refuses a destination owned by another organization" do
      other = create(:organization).backup_destinations.create!(
        name: "Theirs", provider: "s3", region: "us-east-1", bucket: "theirs",
        access_key_id: "access", secret_access_key: "secret"
      )

      patch "/api/organizations/#{organization.id}/backup-destinations/defaults", headers: headers,
        params: { destination_ids: [ other.id ] }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(organization.reload.default_backup_destination_ids).to eq([])
    end

    it "forbids regular members from changing the default" do
      member = create(:user, :admin)
      create(:organization_membership, user: member, organization: organization, role: :member)
      member_headers = auth_headers(member).merge("X-Organization-ID" => organization.id.to_s)

      patch "/api/organizations/#{organization.id}/backup-destinations/defaults", headers: member_headers,
        params: { destination_ids: [ destination.id ] }, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    # A destination left in the default after deletion would surface in every
    # service's picker and fail validation on the next backup.
    it "forgets a deleted destination" do
      organization.update!(default_backup_destination_ids: [ destination.id ])

      delete "/api/organizations/#{organization.id}/backup-destinations/#{destination.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(organization.reload.default_backup_destination_ids).to eq([])
    end
  end
end
