require "rails_helper"

RSpec.describe "Api::ServersController", type: :request do
  let(:user) { create(:user) }
  let!(:server) { create(:server) }
  let(:organization) { server.organization }
  let!(:membership) { create(:organization_membership, user: user, organization: organization, role: :owner) }
  let(:org_headers) { auth_headers(user).merge("X-Organization-ID" => organization.id.to_s) }

  describe "GET /api/servers" do
    context "when unauthenticated" do
      it "returns 401" do
        get "/api/servers"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "returns organization servers" do
        get "/api/servers", headers: org_headers

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
      it "creates an organization server with disconnected status" do
        expect {
          post "/api/servers", params: valid_params, headers: org_headers
        }.to change(Server, :count).by(1)

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json["name"]).to eq("Production Server")
        expect(json["status"]).to eq("disconnected")

        created = Server.order(:id).last
        expect(created.organization_id).to eq(organization.id)
        expect(created.user_id).to be_nil
      end

      it "returns 422 with invalid data" do
        post "/api/servers", params: { server: { name: "", host: "" } }, headers: org_headers

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "returns 403 without an organization for non-admins" do
        regular_user = create(:user, admin: false)

        post "/api/servers", params: valid_params, headers: auth_headers(regular_user)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /api/servers/test" do
    let(:test_params) { { server: { host: "192.168.1.100" } } }

    context "when unauthenticated" do
      it "returns 401" do
        post "/api/servers/test", params: test_params
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "returns test result" do
        result = {
          success: true,
          host: "192.168.1.100",
          host_key_fingerprint: "SHA256:abc",
          dokku_version: "0.35.0",
          docker_version: "26.0.0"
        }
        service = instance_double(ServerTestService, test: result)
        allow(ServerTestService).to receive(:new).with(organization: organization, host: "192.168.1.100", ssh_user: nil).and_return(service)

        post "/api/servers/test", params: test_params, headers: org_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["host_key_fingerprint"]).to eq("SHA256:abc")
      end

      it "returns 422 without an organization" do
        post "/api/servers/test", params: test_params, headers: auth_headers(user)

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
        allow(engine).to receive(:run).with("proxy:report --global --proxy-global-type").and_return(
          { success: true, output: "nginx" }
        )

        host_engine = instance_double(HostEngine)
        allow(HostEngine).to receive(:new).with(server).and_return(host_engine)
        allow(host_engine).to receive(:host_info).and_return({ os: "Ubuntu 22.04", uptime: "up 10 days" })

        post "/api/servers/#{server.id}/validate", headers: org_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["dokku_version"]).to eq("0.35.0")

        server.reload
        expect(server.status).to eq("connected")
        expect(server.dokku_version).to eq("0.35.0")
        expect(server.os).to eq("Ubuntu 22.04")
      end

      it "sets server status to error on failed validation" do
        engine = instance_double(DokkuEngine)
        allow(DokkuEngine).to receive(:new).with(server).and_return(engine)
        allow(engine).to receive(:validate_connection).and_return(
          { success: false, output: "Connection refused" }
        )

        post "/api/servers/#{server.id}/validate", headers: org_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false

        server.reload
        expect(server.status).to eq("error")
      end

      it "returns 404 for non-existent server" do
        post "/api/servers/999999/validate", headers: org_headers

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
        engine = instance_double(HostEngine)
        allow(HostEngine).to receive(:new).with(server).and_return(engine)
        allow(engine).to receive(:run).with("top -bn1 | awk '/%Cpu/{gsub(/,/, \".\"); print 100-$8}'").and_return(
          { success: true, output: "38" }
        )
        allow(engine).to receive(:run).with("free -m | awk 'NR==2{printf \"%.0f\", $3*100/$2 }'").and_return(
          { success: true, output: "62" }
        )
        allow(engine).to receive(:run).with("df -h / | awk 'NR==2{print $5}' | sed 's/%//'").and_return(
          { success: true, output: "38" }
        )

        get "/api/servers/#{server.id}/metrics", headers: org_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["cpu"]).to eq(38)
        expect(json["memory"]).to eq(62)
        expect(json["disk"]).to eq(38)
      end

      it "returns zeroed metrics when ssh_key is blank" do
        server_without_key = create(:server, ssh_key: nil, organization: organization)

        get "/api/servers/#{server_without_key.id}/metrics", headers: org_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["cpu"]).to eq(0)
        expect(json["memory"]).to eq(0)
        expect(json["disk"]).to eq(0)
      end

      it "returns 404 for non-existent server" do
        get "/api/servers/999999/metrics", headers: org_headers

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
          delete "/api/servers/#{server.id}", headers: org_headers
        }.to change(Server, :count).by(-1)

        expect(response).to have_http_status(:no_content)
      end

      it "returns 404 for non-existent server" do
        delete "/api/servers/999999", headers: org_headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
