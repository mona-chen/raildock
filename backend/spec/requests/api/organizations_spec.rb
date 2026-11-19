require "rails_helper"

RSpec.describe "Api::OrganizationsController", type: :request do
  let(:user) { create(:user, :admin) }
  let(:other_user) { create(:user, :admin) }

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

  describe "PATCH /api/organizations/:id" do
    let(:org) { create(:organization, owner: user) }

    before do
      create(:organization_membership, user: user, organization: org, role: :owner)
    end

    it "updates the organization profile for an owner" do
      patch "/api/organizations/#{org.id}",
        params: {
          organization: {
            name: "Acme Platform",
            slug: "acme-platform",
            avatar_url: "https://example.com/acme.png"
          }
        },
        headers: auth_headers(user),
        as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["name"]).to eq("Acme Platform")
      expect(response.parsed_body["slug"]).to eq("acme-platform")
      expect(response.parsed_body["avatar_url"]).to eq("https://example.com/acme.png")
      expect(org.reload.name).to eq("Acme Platform")
    end

    it "allows an admin to update the organization profile" do
      admin_user = create(:user)
      create(:organization_membership, user: admin_user, organization: org, role: :admin)

      patch "/api/organizations/#{org.id}",
        params: { organization: { name: "Admin Renamed" } },
        headers: auth_headers(admin_user),
        as: :json

      expect(response).to have_http_status(:ok)
      expect(org.reload.name).to eq("Admin Renamed")
    end

    it "refuses a regular member" do
      member_user = create(:user)
      create(:organization_membership, user: member_user, organization: org, role: :member)

      patch "/api/organizations/#{org.id}",
        params: { organization: { name: "Member Renamed" } },
        headers: auth_headers(member_user),
        as: :json

      expect(response).to have_http_status(:forbidden)
      expect(org.reload.name).not_to eq("Member Renamed")
    end

    it "reports a duplicate slug" do
      create(:organization, slug: "taken-slug")

      patch "/api/organizations/#{org.id}",
        params: { organization: { slug: "taken-slug" } },
        headers: auth_headers(user),
        as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("Slug")
      expect(org.reload.slug).not_to eq("taken-slug")
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

    it "refuses to delete an organization whose projects still own services" do
      server = create(:server, organization: org)
      project = create(:project, organization: org, server: server)
      create(:service, project: project)

      delete "/api/organizations/#{org.id}", headers: auth_headers(user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["code"]).to eq("dependent_records_present")
      expect(Organization.exists?(org.id)).to be true
      expect(Service.count).to eq(1)
    end

    it "returns 403 for non-owners" do
      create(:organization_membership, user: other_user, organization: org, role: :member)
      delete "/api/organizations/#{org.id}", headers: auth_headers(other_user)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
