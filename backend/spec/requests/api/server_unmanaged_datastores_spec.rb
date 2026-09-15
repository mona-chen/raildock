require "rails_helper"

RSpec.describe "Server unmanaged datastores API", type: :request do
  let(:owner) { create(:user) }
  let(:organization) { create(:organization, owner: owner) }
  let(:server) { create(:server, organization: organization) }
  let(:project) { create(:project, name: "tween", server: server, organization: organization) }
  let(:headers) { auth_headers(owner).merge("X-Organization-ID" => organization.id.to_s) }
  let(:scanner) { instance_double(UnmanagedDatastoreScanner) }

  let(:resource) do
    {
      name: "tween-jean-postgres",
      subtype: "postgres",
      service_type: "database",
      status: "running",
      linked_apps: [ "tween-jean-646e2ba9" ]
    }
  end

  before do
    create(:organization_membership, user: owner, organization: organization, role: :owner)
    allow(UnmanagedDatastoreScanner).to receive(:new).with(server).and_return(scanner)
    allow(scanner).to receive(:scan).and_return(success: true, resources: [ resource ], errors: [])
  end

  describe "GET /api/servers/:server_id/unmanaged_datastores" do
    it "returns the datastores RailDock does not track" do
      get "/api/servers/#{server.id}/unmanaged_datastores", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["resources"].length).to eq(1)
      expect(json["resources"].first["name"]).to eq("tween-jean-postgres")
      expect(json["resources"].first["linked_apps"]).to eq([ "tween-jean-646e2ba9" ])
    end

    it "returns 422 when the host cannot be scanned" do
      allow(scanner).to receive(:scan).and_return(success: false, error: "ssh refused", resources: [], errors: [])

      get "/api/servers/#{server.id}/unmanaged_datastores", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("ssh refused")
    end

    it "forbids non-admins" do
      member = create(:user, admin: false)
      create(:organization_membership, user: member, organization: organization, role: :member)
      member_headers = auth_headers(member).merge("X-Organization-ID" => organization.id.to_s)

      get "/api/servers/#{server.id}/unmanaged_datastores", headers: member_headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/servers/:server_id/unmanaged_datastores/adopt" do
    it "records the existing datastore in the project" do
      expect {
        post "/api/servers/#{server.id}/unmanaged_datastores/adopt",
          params: { resource_name: "tween-jean-postgres", project_id: project.id },
          headers: headers
      }.to change(Service, :count).by(1)

      expect(response).to have_http_status(:created)

      service = Service.last
      expect(service.project).to eq(project)
      expect(service.name).to eq("jean-postgres")
      expect(service.dokku_app_name).to eq("tween-jean-postgres")
      expect(service.managed_by).to eq("ui")
    end

    it "returns 422 when the resource is not there" do
      post "/api/servers/#{server.id}/unmanaged_datastores/adopt",
        params: { resource_name: "ghost-db", project_id: project.id },
        headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("not found")
    end

    it "returns 404 for a project outside the organization" do
      other_project = create(:project, server: create(:server, organization: organization))

      post "/api/servers/#{server.id}/unmanaged_datastores/adopt",
        params: { resource_name: "tween-jean-postgres", project_id: other_project.id },
        headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
