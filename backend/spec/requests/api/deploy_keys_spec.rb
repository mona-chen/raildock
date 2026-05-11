require "rails_helper"

RSpec.describe "Api::DeployKeysController", type: :request do
  let(:user) { create(:user) }
  let(:org) { create(:organization, owner: user) }

  before do
    create(:organization_membership, user: user, organization: org, role: :owner)
  end

  describe "GET /api/deploy-keys" do
    it "returns 401 when unauthenticated" do
      get "/api/deploy-keys"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns user's deploy keys" do
      key = create(:deploy_key, user: user, name: "my-key")
      get "/api/deploy-keys", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.length).to eq(1)
      expect(json.first["name"]).to eq("my-key")
    end
  end

  describe "POST /api/deploy-keys" do
    it "creates a deploy key for the user" do
      expect {
        post "/api/deploy-keys", params: { name: "production" }, headers: auth_headers(user)
      }.to change(DeployKey, :count).by(1)

      expect(response).to have_http_status(:created)
      key = DeployKey.last
      expect(key.name).to eq("production")
      expect(key.public_key).to start_with("ssh-ed25519")
      expect(key.fingerprint).to be_present
    end

    it "creates a deploy key for an organization" do
      expect {
        post "/api/organizations/#{org.id}/deploy-keys", params: { name: "team-key" }, headers: auth_headers(user)
      }.to change(DeployKey, :count).by(1)

      expect(response).to have_http_status(:created)
      key = DeployKey.last
      expect(key.organization).to eq(org)
      expect(key.public_key).to start_with("ssh-ed25519")
    end
  end

  describe "DELETE /api/deploy-keys/:id" do
    it "deletes the deploy key" do
      key = create(:deploy_key, user: user, name: "old-key")
      expect {
        delete "/api/deploy-keys/#{key.id}", headers: auth_headers(user)
      }.to change(DeployKey, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end
