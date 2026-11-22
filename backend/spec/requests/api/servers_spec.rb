require "rails_helper"

RSpec.describe "Api::ServersController", type: :request do
  let(:user) { create(:user, :admin) }
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
        allow(ServerTestService).to receive(:new).with(organization: organization, host: "192.168.1.100", ssh_user: nil, ssh_port: nil).and_return(service)

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
          { success: true, dokku_version: "0.35.0", docker_version: "26.0.0", os: nil, uptime: "10d" }
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

  describe "GET /api/servers/:id/metrics_history" do
    it "returns retained samples even when collection is disabled" do
      server.server_metrics.create!(sampled_at: 5.minutes.ago, data: { available: true, cpu: 0.05 })
      SystemSetting.set!("metrics_hosts_enabled", "false")
      get "/api/servers/#{server.id}/metrics_history?hours=1", headers: org_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["collection_enabled"]).to be(false)
      expect(response.parsed_body["samples"].first["cpu"]).to eq(0.05)
      expect(HostMetricsCollector).not_to receive(:call)
      get "/api/servers/#{server.id}/metrics", headers: org_headers
      expect(response.parsed_body["collection_enabled"]).to be(false)
    end

    it "does not expose another organization's samples to an organization owner" do
      user.update!(admin: false)
      foreign = create(:server)
      foreign.server_metrics.create!(sampled_at: Time.current, data: { cpu: 99 })
      get "/api/servers/#{foreign.id}/metrics_history", headers: org_headers
      expect(response).to have_http_status(:not_found)
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
        sample = server.server_metrics.create!(sampled_at: Time.current, data: { available: true, cpu: 38, memory: 62, disk: 38 })
        allow(HostMetricsCollector).to receive(:call).with(server).and_return(sample)

        get "/api/servers/#{server.id}/metrics", headers: org_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["cpu"]).to eq(38)
        expect(json["memory"]).to eq(62)
        expect(json["disk"]).to eq(38)
      end

      it "returns unavailable metrics when ssh_key is blank" do
        server_without_key = create(:server, ssh_key: nil, organization: organization)

        get "/api/servers/#{server_without_key.id}/metrics", headers: org_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["cpu"]).to be_nil
        expect(json["memory"]).to be_nil
        expect(json["disk"]).to be_nil
      end

      it "returns 404 for non-existent server" do
        get "/api/servers/999999/metrics", headers: org_headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PATCH /api/servers/:id" do
    it "does not let the client overwrite the pinned host key" do
      server.update!(host_key: "ssh-ed25519 AAAAoriginal", host_key_fingerprint: "SHA256:original")

      patch "/api/servers/#{server.id}",
        params: { server: { name: "Renamed", host_key: "ssh-ed25519 AAAAattacker", host_key_fingerprint: "SHA256:attacker" } },
        headers: org_headers

      expect(response).to have_http_status(:ok)
      server.reload
      expect(server.name).to eq("Renamed")
      expect(server.host_key).to eq("ssh-ed25519 AAAAoriginal")
      expect(server.host_key_fingerprint).to eq("SHA256:original")
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

      it "refuses to delete a server that projects still run on" do
        create(:project, server: server, organization: organization, name: "Storefront")

        expect {
          delete "/api/servers/#{server.id}", headers: org_headers
        }.not_to change(Server, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        body = response.parsed_body
        expect(body["code"]).to eq("server_has_projects")
        expect(body["projects"]).to eq([ "Storefront" ])
        expect(body["error"]).to include("Storefront")
      end

      it "refuses to delete a server that still holds backup destinations" do
        server.backup_destinations.create!(
          name: "Off-host S3", provider: "s3", region: "us-east-1", bucket: "tween-backups"
        )

        expect {
          delete "/api/servers/#{server.id}", headers: org_headers
        }.not_to change(Server, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["code"]).to eq("dependent_records_present")
        expect(response.parsed_body["error"]).to include("backup destination")
      end

      it "deletes the server once its backup destinations are removed" do
        destination = server.backup_destinations.create!(
          name: "Off-host S3", provider: "s3", region: "us-east-1", bucket: "tween-backups"
        )
        destination.destroy!

        expect {
          delete "/api/servers/#{server.id}", headers: org_headers
        }.to change(Server, :count).by(-1)

        expect(response).to have_http_status(:no_content)
      end
    end
  end
end
