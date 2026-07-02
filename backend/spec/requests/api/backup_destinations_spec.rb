require "rails_helper"

RSpec.describe "Organization backup destinations", type: :request do
  let(:user) { create(:user) }
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
    verifier = instance_double(BackupDestinationClient, verify!: true)
    allow(BackupDestinationClient).to receive(:new).and_return(verifier)

    post "/api/organizations/#{organization.id}/backup-destinations", headers: headers, params: {
      name: "R2", provider: "r2", endpoint: "https://r2.example.com",
      region: "auto", bucket: "backups", access_key_id: "access", secret_access_key: "secret"
    }, as: :json

    expect(response).to have_http_status(:created)
    body = response.parsed_body
    expect(body).to include("name" => "R2", "configured" => true)
    expect(body["recovery_key"]).to match(/\A[0-9a-f]{64}\z/)
    expect(organization.backup_destinations.count).to eq(1)
  end

  it "returns an error when verification fails" do
    allow_any_instance_of(BackupDestinationClient).to receive(:verify!).and_raise("Invalid credentials")

    post "/api/organizations/#{organization.id}/backup-destinations", headers: headers, params: {
      name: "R2", provider: "r2", region: "auto", bucket: "backups",
      access_key_id: "access", secret_access_key: "secret"
    }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include("error" => /verification failed/i)
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
    other_user = create(:user)
    other_headers = auth_headers(other_user)

    get "/api/organizations/#{organization.id}/backup-destinations", headers: other_headers

    expect(response).to have_http_status(:forbidden)
  end

  it "forbids regular members from creating destinations" do
    member = create(:user)
    create(:organization_membership, user: member, organization: organization, role: :member)
    member_headers = auth_headers(member).merge("X-Organization-ID" => organization.id.to_s)

    post "/api/organizations/#{organization.id}/backup-destinations", headers: member_headers, params: {
      name: "S3", provider: "s3", region: "us-east-1", bucket: "backups",
      access_key_id: "access", secret_access_key: "secret"
    }, as: :json

    expect(response).to have_http_status(:forbidden)
  end
end
