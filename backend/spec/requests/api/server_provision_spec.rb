require "rails_helper"

RSpec.describe "Api::ServersController provision", type: :request do
  let(:user) { create(:user, admin: false) }
  let(:organization) { create(:organization, owner: user) }
  let!(:membership) { create(:organization_membership, user: user, organization: organization, role: :owner) }
  let(:org_headers) { auth_headers(user).merge("X-Organization-ID" => organization.id.to_s) }

  it "enqueues a ProvisionServerJob and returns a setup_id" do
    OrganizationSshKeyService.generate(organization)

    expect {
      post "/api/servers/provision", params: { server: { host: "192.168.1.60", admin_user: "root" } }, headers: org_headers
    }.to have_enqueued_job(ProvisionServerJob)

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["setup_id"]).to be_present
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
    around do |example|
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
      Rails.cache = original
    end

    it "returns the cached setup progress" do
      setup_id = SecureRandom.uuid
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

    it "returns 400 when setup_id is missing" do
      get "/api/servers/provision_status", headers: org_headers
      expect(response).to have_http_status(:bad_request)
    end
  end
end
