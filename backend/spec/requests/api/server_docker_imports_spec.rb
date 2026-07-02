require "rails_helper"

RSpec.describe "Server Docker imports API", type: :request do
  let(:owner) { create(:user) }
  let(:organization) { create(:organization, owner: owner) }
  let(:server) { create(:server, organization: organization) }
  let(:headers) { auth_headers(owner).merge("X-Organization-ID" => organization.id.to_s) }

  before do
    create(:organization_membership, user: owner, organization: organization, role: :owner)
  end

  describe "GET /api/servers/:server_id/docker_imports" do
    it "returns scanned containers" do
      scanner = instance_double(DockerContainerScanner)
      allow(DockerContainerScanner).to receive(:new).with(server).and_return(scanner)
      allow(scanner).to receive(:scan).and_return(
        success: true,
        containers: [
          { id: "abc", name: "web", image: "web:latest", status: "running", running: true, created: Time.current.iso8601,
            ports: [], env: {}, mounts: [], labels: {}, service_type: "app", subtype: nil }
        ]
      )

      get "/api/servers/#{server.id}/docker_imports", headers: headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.length).to eq(1)
      expect(json.first["name"]).to eq("web")
    end

    it "returns 422 when scanning fails" do
      scanner = instance_double(DockerContainerScanner)
      allow(DockerContainerScanner).to receive(:new).with(server).and_return(scanner)
      allow(scanner).to receive(:scan).and_return(success: false, error: "docker down")

      get "/api/servers/#{server.id}/docker_imports", headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("docker down")
    end

    it "forbids non-admins" do
      member = create(:user, admin: false)
      create(:organization_membership, user: member, organization: organization, role: :member)
      member_headers = auth_headers(member).merge("X-Organization-ID" => organization.id.to_s)

      get "/api/servers/#{server.id}/docker_imports", headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/servers/:server_id/docker_imports" do
    it "imports selected containers" do
      allow(DeploymentJob).to receive(:perform_later)

      post "/api/servers/#{server.id}/docker_imports",
        params: {
          containers: [
            { id: "abc", name: "web", image: "web:latest", status: "running", running: true, created: Time.current.iso8601,
              ports: [ { container_port: "3000", host_port: "8080", host_ip: "0.0.0.0" } ],
              env: { "PORT" => "3000" }, mounts: [], labels: {}, service_type: "app", subtype: nil }
          ]
        },
        headers: headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["project_name"]).to eq("Imported Containers")
      expect(json["results"].first["success"]).to be true
    end

    it "returns 422 when no containers are selected" do
      post "/api/servers/#{server.id}/docker_imports", params: { containers: [] }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
