require "rails_helper"

RSpec.describe "Api::ServersController", type: :request do
  let(:user) { create(:user) }
  let!(:server) { create(:server) }

  describe "GET /api/servers" do
    context "when unauthenticated" do
      it "returns 401" do
        get "/api/servers"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "returns all servers" do
        get "/api/servers", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json.length).to eq(1)
        expect(json.first["id"]).to eq(server.id)
      end
    end
  end

  describe "POST /api/servers" do
    let(:valid_params) do
      {
        server: {
          name: "Production Server",
          host: "192.168.1.100",
          ssh_key: "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----",
          default_proxy: "traefik"
        }
      }
    end

    context "when unauthenticated" do
      it "returns 401" do
        post "/api/servers", params: valid_params
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "creates a server with disconnected status" do
        expect {
          post "/api/servers", params: valid_params, headers: auth_headers(user)
        }.to change(Server, :count).by(1)

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json["name"]).to eq("Production Server")
        expect(json["status"]).to eq("disconnected")
      end

      it "returns 422 with invalid data" do
        post "/api/servers", params: { server: { name: "", host: "" } }, headers: auth_headers(user)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "POST /api/servers/:id/validate" do
    context "when unauthenticated" do
      it "returns 401" do
        post "/api/servers/#{server.id}/validate"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "validates connection and updates server on success" do
        engine = instance_double(DokkuEngine)
        allow(DokkuEngine).to receive(:new).with(server).and_return(engine)
        allow(engine).to receive(:validate_connection).and_return(
          { success: true, dokku_version: "0.35.0", docker_version: "26.0.0", os: "Ubuntu", uptime: "10d" }
        )
        allow(engine).to receive(:run).with("proxy:report").and_return(
          { success: true, output: "nginx enabled" }
        )

        post "/api/servers/#{server.id}/validate", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["dokku_version"]).to eq("0.35.0")

        server.reload
        expect(server.status).to eq("connected")
        expect(server.dokku_version).to eq("0.35.0")
      end

      it "sets server status to error on failed validation" do
        engine = instance_double(DokkuEngine)
        allow(DokkuEngine).to receive(:new).with(server).and_return(engine)
        allow(engine).to receive(:validate_connection).and_return(
          { success: false, output: "Connection refused" }
        )

        post "/api/servers/#{server.id}/validate", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false

        server.reload
        expect(server.status).to eq("error")
      end

      it "returns 404 for non-existent server" do
        post "/api/servers/999999/validate", headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /api/servers/:id/metrics" do
    context "when unauthenticated" do
      it "returns 401" do
        get "/api/servers/#{server.id}/metrics"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "returns real metrics when ssh_key is present" do
        engine = instance_double(DokkuEngine)
        allow(DokkuEngine).to receive(:new).with(server).and_return(engine)
        allow(engine).to receive(:run).with("docker system info --format '{{.NCPU}}'").and_return(
          { success: true, output: "4" }
        )
        allow(engine).to receive(:run).with("free -m | awk 'NR==2{printf \"%.0f\", $3*100/$2 }'").and_return(
          { success: true, output: "62" }
        )
        allow(engine).to receive(:run).with("df -h / | awk 'NR==2{print $5}' | sed 's/%//'").and_return(
          { success: true, output: "38" }
        )

        get "/api/servers/#{server.id}/metrics", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["cpu"]).to eq(4)
        expect(json["memory"]).to eq(62)
        expect(json["disk"]).to eq(38)
      end

      it "returns zeroed metrics when ssh_key is blank" do
        server_without_key = create(:server, ssh_key: nil)

        get "/api/servers/#{server_without_key.id}/metrics", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["cpu"]).to eq(0)
        expect(json["memory"]).to eq(0)
        expect(json["disk"]).to eq(0)
      end

      it "returns 404 for non-existent server" do
        get "/api/servers/999999/metrics", headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "DELETE /api/servers/:id" do
    context "when unauthenticated" do
      it "returns 401" do
        delete "/api/servers/#{server.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "destroys the server" do
        expect {
          delete "/api/servers/#{server.id}", headers: auth_headers(user)
        }.to change(Server, :count).by(-1)

        expect(response).to have_http_status(:no_content)
      end

      it "returns 404 for non-existent server" do
        delete "/api/servers/999999", headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
