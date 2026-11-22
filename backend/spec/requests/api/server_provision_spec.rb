require "rails_helper"

RSpec.describe "Api::ServersController provision", type: :request do
  let(:user) { create(:user, admin: false) }
  let(:organization) { create(:organization, owner: user) }
  let!(:membership) { create(:organization_membership, user: user, organization: organization, role: :owner) }
  let(:org_headers) { auth_headers(user).merge("X-Organization-ID" => organization.id.to_s) }

  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original
  end

  it "enqueues a ProvisionServerJob and returns a setup_id" do
    OrganizationSshKeyService.generate(organization)

    expect {
      post "/api/servers/provision", params: { server: { host: "192.168.1.60", admin_user: "root" } }, headers: org_headers
    }.to have_enqueued_job(ProvisionServerJob)

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["setup_id"]).to be_present
  end

  it "broadcasts on the setup id the client proposed so its subscription receives progress" do
    client_id = SecureRandom.uuid

    expect {
      post "/api/servers/provision", params: { server: { host: "192.168.1.60", setup_id: client_id } }, headers: org_headers
    }.to have_enqueued_job(ProvisionServerJob).with(client_id, organization.id, "192.168.1.60", "root", anything, hash_including(proxy_mode: "managed"))

    expect(response.parsed_body["setup_id"]).to eq(client_id)
    expect(Server.setup_accessible_by?(client_id, user, organization: organization)).to be(true)
  end

  it "mints its own id when the proposed one is not a UUID or already claimed" do
    post "/api/servers/provision", params: { server: { host: "192.168.1.60", setup_id: "../../etc" } }, headers: org_headers
    expect(response.parsed_body["setup_id"]).to match(Server::SETUP_ID_FORMAT)

    claimed = SecureRandom.uuid
    Server.record_setup_owner!(claimed, organization_id: create(:organization).id, user_id: create(:user).id)
    post "/api/servers/provision", params: { server: { host: "192.168.1.61", setup_id: claimed } }, headers: org_headers
    expect(response.parsed_body["setup_id"]).not_to eq(claimed)
  end

  it "fails fast when the host is already connected in this organization" do
    create(:server, organization: organization, host: "192.168.1.60", name: "Existing box")

    expect {
      post "/api/servers/provision", params: { server: { host: "192.168.1.60" } }, headers: org_headers
    }.not_to have_enqueued_job(ProvisionServerJob)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("server_exists")
    expect(response.parsed_body["error"]).to include("Existing box")
  end

  it "rejects an unknown proxy mode" do
    expect {
      post "/api/servers/provision", params: { server: { host: "192.168.1.60", proxy_mode: "managed;reboot" } }, headers: org_headers
    }.not_to have_enqueued_job(ProvisionServerJob)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("invalid_proxy_mode")
  end

  it "returns 422 without an organization" do
    post "/api/servers/provision", params: { server: { host: "192.168.1.60" } }, headers: auth_headers(user)
    expect(response).to have_http_status(:forbidden)
  end

  it "returns 403 for non-owner members" do
    member = create(:user, admin: false)
    create(:organization_membership, user: member, organization: organization, role: :member)

    post "/api/servers/provision", params: { server: { host: "192.168.1.60" } }, headers: auth_headers(member).merge("X-Organization-ID" => organization.id.to_s)
    expect(response).to have_http_status(:forbidden)
  end

  describe "GET /api/servers/provision_status" do
    it "returns the cached setup progress" do
      setup_id = SecureRandom.uuid
      Server.record_setup_owner!(setup_id, organization_id: organization.id, user_id: user.id)
      SetupProgress.start(setup_id)
      SetupProgress.log(setup_id, "Bootstrap started")
      SetupProgress.complete(setup_id, server_id: "server-123")

      get "/api/servers/provision_status", params: { setup_id: setup_id }, headers: org_headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["state"]).to eq("completed")
      expect(json["server_id"]).to eq("server-123")
      expect(json["logs"].map { |l| l["line"] }).to include("Bootstrap started")
    end

    it "returns 404 for a setup started by another organization" do
      setup_id = SecureRandom.uuid
      other_owner = create(:user, admin: false)
      other_org = create(:organization, owner: other_owner)
      Server.record_setup_owner!(setup_id, organization_id: other_org.id, user_id: other_owner.id)
      SetupProgress.start(setup_id)

      get "/api/servers/provision_status", params: { setup_id: setup_id }, headers: org_headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for an unknown setup id" do
      get "/api/servers/provision_status", params: { setup_id: SecureRandom.uuid }, headers: org_headers
      expect(response).to have_http_status(:not_found)
    end

    it "returns 400 when setup_id is missing" do
      get "/api/servers/provision_status", headers: org_headers
      expect(response).to have_http_status(:bad_request)
    end
  end
end
