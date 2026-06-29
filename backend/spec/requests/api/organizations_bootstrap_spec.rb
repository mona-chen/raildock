require "rails_helper"

RSpec.describe "Organization server bootstrap", type: :request do
  let(:owner) { create(:user) }
  let(:organization) { create(:organization, owner: owner) }
  let(:headers) { auth_headers(owner).merge("X-Organization-ID" => organization.id.to_s) }

  before do
    create(:organization_membership, user: owner, organization: organization, role: :owner)
  end

  describe "GET /api/organizations/:id/server_bootstrap" do
    it "returns the public key and bootstrap command for owners" do
      get "/api/organizations/#{organization.id}/server_bootstrap", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["public_key"]).to start_with("ssh-ed25519 ")
      expect(json["command"]).to include("/bootstrap.sh")
      expect(json["command"]).to include(json["public_key"].split.first) # key type
    end

    it "forbids members" do
      member = create(:user)
      create(:organization_membership, user: member, organization: organization, role: :member)
      member_headers = auth_headers(member).merge("X-Organization-ID" => organization.id.to_s)

      get "/api/organizations/#{organization.id}/server_bootstrap", headers: member_headers

      expect(response).to have_http_status(:forbidden)
    end
  end
end
