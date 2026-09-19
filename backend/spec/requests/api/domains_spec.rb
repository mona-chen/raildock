require 'rails_helper'

RSpec.describe "Domains API", type: :request do
  let(:user) { create(:user) }
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:service) { create(:service, project: project, status: :running) }
  let(:auth_headers) { { "Authorization" => "Bearer #{user.generate_jwt}" } }
  let(:engine) { instance_double(DokkuEngine) }

  before do
    allow(DokkuEngine).to receive(:new).with(server).and_return(engine)
    allow(engine).to receive(:with_session).and_yield
    allow(engine).to receive(:domain_add).and_return(success: true, output: "")
    allow(engine).to receive(:domain_remove).and_return(success: true, output: "")
    allow(engine).to receive(:ports_set).and_return(success: true, output: "")
    allow(engine).to receive(:ps_rebuild).and_return(success: true, output: "")
    allow(engine).to receive(:traefik_show_config).and_return(success: true, output: "")
    allow(engine).to receive(:run).and_return(success: true, output: "")
  end

  describe "POST /api/services/:service_id/domains" do
    it "creates a domain" do
      post "/api/services/#{service.id}/domains",
        params: { hostname: "example.com", port: 443 },
        headers: auth_headers
      expect(response).to have_http_status(:created)
      expect(service.domains.count).to eq(1)
    end

    it "leaves target_port blank so the domain follows the app" do
      service.update!(detected_port: 3001)

      post "/api/services/#{service.id}/domains",
        params: { hostname: "example.com", port: 443 },
        headers: auth_headers

      domain = service.domains.find_by!(hostname: "example.com")
      expect(domain.target_port).to be_nil
      expect(domain.resolved_target_port).to eq(3001)
      expect(engine).to have_received(:ports_set).with(service.dokku_app_name, "http:80:3001", "https:443:3001")
    end

    it "stores an explicit target_port and rebuilds when it moves the app port" do
      service.update!(detected_port: 3000)

      post "/api/services/#{service.id}/domains",
        params: { hostname: "example.com", port: 443, target_port: 8080 },
        headers: auth_headers

      expect(service.domains.find_by!(hostname: "example.com").target_port).to eq(8080)
      expect(engine).to have_received(:ports_set).with(service.dokku_app_name, "http:80:8080", "https:443:8080")
      expect(engine).to have_received(:ps_rebuild).with(service.dokku_app_name)
      expect(service.reload.detected_port).to eq(8080)
    end

    it "does not rebuild when the port is unchanged" do
      service.update!(detected_port: 3000)

      post "/api/services/#{service.id}/domains",
        params: { hostname: "example.com", port: 443 },
        headers: auth_headers

      expect(engine).not_to have_received(:ps_rebuild)
    end

    it "is idempotent for an identical resubmission" do
      create(:domain, service: service, hostname: "example.com", ssl: true, target_port: nil)

      post "/api/services/#{service.id}/domains",
        params: { hostname: "example.com", port: 443 },
        headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(service.domains.where(hostname: "example.com").count).to eq(1)
      expect(engine).not_to have_received(:domain_add)
    end

    it "reports a conflict when the existing domain differs" do
      create(:domain, service: service, hostname: "example.com", ssl: true, target_port: 3000)

      post "/api/services/#{service.id}/domains",
        params: { hostname: "example.com", port: 443, target_port: 4000 },
        headers: auth_headers

      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)).to include("code" => "domain_exists")
      expect(engine).not_to have_received(:domain_add)
    end

    it "rolls the record back when the host rejects the domain" do
      allow(engine).to receive(:domain_add).and_return(success: false, output: "boom")

      post "/api/services/#{service.id}/domains",
        params: { hostname: "example.com", port: 443 },
        headers: auth_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("boom")
      expect(service.domains.where(hostname: "example.com")).to be_empty
      expect(engine).to have_received(:domain_remove).with(service.dokku_app_name, "example.com")
    end

    context "with an external proxy" do
      let(:server) { create(:server, proxy_mode: "external", external_proxy_network: "traefik") }
      let(:host_engine) { instance_double(HostEngine) }
      let(:configurator) { instance_double(ExternalProxyConfigurator, apply!: { success: true }) }

      before do
        allow(HostEngine).to receive(:new).with(server).and_return(host_engine)
        allow(host_engine).to receive(:with_session).and_yield
        allow(ExternalProxyConfigurator).to receive(:new).and_return(configurator)
      end

      it "refreshes all labels and rebuilds the running container" do
        post "/api/services/#{service.id}/domains",
          params: { hostname: "api.example.com" },
          headers: auth_headers

        expect(configurator).to have_received(:apply!)
        expect(engine).to have_received(:ps_rebuild).with(service.dokku_app_name)
      end
    end

    it "returns 422 with invalid data" do
      post "/api/services/#{service.id}/domains",
        params: { hostname: "" },
        headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 401 without auth" do
      post "/api/services/#{service.id}/domains", params: { hostname: "example.com" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/domains/:id" do
    let!(:domain) { create(:domain, service: service, hostname: "test.com", target_port: 3000) }

    it "edits the target port" do
      patch "/api/domains/#{domain.id}",
        params: { target_port: 4000 },
        headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(domain.reload.target_port).to eq(4000)
      expect(engine).to have_received(:ports_set).with(service.dokku_app_name, "http:80:4000")
    end

    it "clears the target port so the domain follows the app again" do
      patch "/api/domains/#{domain.id}",
        params: { target_port: "" },
        headers: auth_headers

      expect(domain.reload.target_port).to be_nil
    end

    it "moves the hostname" do
      patch "/api/domains/#{domain.id}",
        params: { hostname: "renamed.com" },
        headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(domain.reload.hostname).to eq("renamed.com")
      expect(engine).to have_received(:domain_remove).with(service.dokku_app_name, "test.com")
      expect(engine).to have_received(:domain_add).with(service.dokku_app_name, "renamed.com")
    end

    it "rejects a hostname another domain already uses" do
      create(:domain, service: service, hostname: "taken.com")

      patch "/api/domains/#{domain.id}",
        params: { hostname: "taken.com" },
        headers: auth_headers

      expect(response).to have_http_status(:conflict)
      expect(domain.reload.hostname).to eq("test.com")
    end

    it "keeps the record untouched when the host rejects the edit" do
      allow(engine).to receive(:domain_add).and_return(success: false, output: "nope")

      patch "/api/domains/#{domain.id}",
        params: { target_port: 4000 },
        headers: auth_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(domain.reload.target_port).to eq(3000)
    end

    it "restores the previous routing when the host rejects the new one" do
      allow(engine).to receive(:ports_set).and_return(success: false, output: "bad mapping")

      patch "/api/domains/#{domain.id}",
        params: { target_port: 4000 },
        headers: auth_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(domain.reload.target_port).to eq(3000)
      expect(engine).to have_received(:ports_set).with(service.dokku_app_name, "http:80:3000")
    end

    it "returns 404 for a domain that does not exist" do
      patch "/api/domains/0",
        params: { target_port: 4000 },
        headers: auth_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/services/:service_id/domains/:hostname" do
    let!(:domain) { create(:domain, service: service, hostname: "test.com") }

    it "destroys the domain" do
      delete "/api/services/#{service.id}/domains/test.com", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(service.domains.count).to eq(0)
    end

    it "is idempotent for a domain that is already gone" do
      delete "/api/services/#{service.id}/domains/missing.com", headers: auth_headers
      expect(response).to have_http_status(:no_content)
    end

    it "keeps the record when the host cannot remove the domain" do
      allow(engine).to receive(:domain_remove).and_return(success: false, output: "stuck")

      delete "/api/services/#{service.id}/domains/test.com", headers: auth_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(service.domains.where(hostname: "test.com")).to exist
    end

    it "destroys a domain whose hostname was saved with a protocol" do
      bad_domain = create(:domain, service: service, hostname: "https://bad.example.com")
      delete "/api/services/#{service.id}/domains/#{CGI.escape(bad_domain.hostname)}", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(service.domains.count).to eq(1)
    end
  end
end
