require "rails_helper"

RSpec.describe "Api::OrganizationsController", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  describe "GET /api/organizations" do
    it "returns 401 when unauthenticated" do
      get "/api/organizations"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns user's organizations" do
      org = create(:organization, owner: user)
      create(:organization_membership, user: user, organization: org, role: :owner)

      get "/api/organizations", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.length).to eq(1)
      expect(json.first["name"]).to eq(org.name)
    end
  end

  describe "POST /api/organizations" do
    let(:valid_params) do
      { organization: { name: "Acme Corp", slug: "acme-corp" } }
    end

    it "creates an organization and makes user the owner" do
      expect {
        post "/api/organizations", params: valid_params, headers: auth_headers(user)
      }.to change(Organization, :count).by(1)
        .and change(OrganizationMembership, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["name"]).to eq("Acme Corp")
      expect(json["slug"]).to eq("acme-corp")

      org = Organization.last
      expect(org.owner).to eq(user)
      expect(org.memberships.find_by(user: user).role).to eq("owner")
    end

    it "returns 422 with invalid data" do
      post "/api/organizations", params: { organization: { name: "" } }, headers: auth_headers(user)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/organizations/:id" do
    let(:org) { create(:organization, owner: user) }

    before do
      create(:organization_membership, user: user, organization: org, role: :owner)
    end

    it "returns the organization" do
      get "/api/organizations/#{org.id}", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["name"]).to eq(org.name)
    end

    it "returns 403 for non-members" do
      get "/api/organizations/#{org.id}", headers: auth_headers(other_user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /api/organizations/:id" do
    let(:org) { create(:organization, owner: user) }

    before do
      create(:organization_membership, user: user, organization: org, role: :owner)
    end

    it "allows owner to delete" do
      delete "/api/organizations/#{org.id}", headers: auth_headers(user)
      expect(response).to have_http_status(:no_content)
      expect(Organization.exists?(org.id)).to be false
    end

    it "returns 403 for non-owners" do
      create(:organization_membership, user: other_user, organization: org, role: :member)
      delete "/api/organizations/#{org.id}", headers: auth_headers(other_user)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
