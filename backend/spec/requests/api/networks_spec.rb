require 'rails_helper'

RSpec.describe "Networks API", type: :request do
  let(:user) { create(:user, admin: false) }
  let(:organization) { create(:organization, owner: user) }
  let!(:membership) { create(:organization_membership, user: user, organization: organization, role: :owner) }
  let(:server) { create(:server, organization: organization) }
  let(:auth_headers) { { "Authorization" => "Bearer #{user.generate_jwt}", "X-Organization-ID" => organization.id.to_s } }
  let(:host_engine) { instance_double(HostEngine) }

  before do
    allow(HostEngine).to receive(:new).with(server).and_return(host_engine)
  end

  describe "GET /api/servers/:id/networks" do
    it "returns networks and recommends the one containing Traefik" do
      allow(host_engine).to receive(:docker_network_inventory).and_return(
        success: true,
        output: {
          Name: "matrix_default",
          Driver: "bridge",
          Scope: "local",
          Internal: false,
          Containers: { "abc" => { "Name" => "matrix-traefik-1" } }
        }.to_json
      )
      allow(host_engine).to receive(:docker_container_inventory).and_return(
        success: true,
        output: {
          "Image" => "traefik:v3.0",
          "Names" => "matrix-traefik-1",
          "Networks" => "matrix_default"
        }.to_json
      )

      get "/api/servers/#{server.id}/networks", headers: auth_headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.first).to include(
        "name" => "matrix_default",
        "recommended" => true,
        "selectable" => true,
        "traefik_containers" => [ "matrix-traefik-1" ]
      )
    end

    it "requires authentication" do
      get "/api/servers/#{server.id}/networks"

      expect(response).to have_http_status(:unauthorized)
    end

    it "does not expose another user's server inventory" do
      other_server = create(:server, user: create(:user))

      get "/api/servers/#{other_server.id}/networks", headers: auth_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/servers/:id/networks/validate" do
    before do
      allow(host_engine).to receive(:docker_network_inventory).and_return(
        success: true,
        output: {
          Name: "matrix_default",
          Driver: "bridge",
          Scope: "local",
          Internal: false,
          Containers: { "abc" => { "Name" => "matrix-traefik-1" } }
        }.to_json
      )
      allow(host_engine).to receive(:docker_container_inventory).and_return(
        success: true,
        output: {
          "Image" => "traefik:v3.0",
          "Names" => "matrix-traefik-1",
          "Networks" => "matrix_default"
        }.to_json
      )
    end

    it "validates a Traefik-connected network" do
      post "/api/servers/#{server.id}/networks/validate",
        params: { network: "matrix_default" },
        headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include(
        "success" => true,
        "network" => "matrix_default"
      )
    end

    it "rejects a missing network" do
      post "/api/servers/#{server.id}/networks/validate",
        params: { network: "missing" },
        headers: auth_headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
