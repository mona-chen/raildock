require 'rails_helper'

RSpec.describe "Domains API", type: :request do
  let(:user) { create(:user) }
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:service) { create(:service, project: project) }
  let(:auth_headers) { { "Authorization" => "Bearer #{user.generate_jwt}" } }

  describe "POST /api/services/:service_id/domains" do
    it "creates a domain" do
      post "/api/services/#{service.id}/domains",
        params: { hostname: "example.com", port: 443 },
        headers: auth_headers
      expect(response).to have_http_status(:created)
      expect(service.domains.count).to eq(1)
    end

    context "with an external proxy" do
      let(:server) { create(:server, proxy_mode: "external", external_proxy_network: "traefik") }
      let(:engine) { instance_double(DokkuEngine) }
      let(:host_engine) { instance_double(HostEngine) }
      let(:configurator) { instance_double(ExternalProxyConfigurator, apply!: { success: true }) }

      before do
        allow(DokkuEngine).to receive(:new).with(server).and_return(engine)
        allow(HostEngine).to receive(:new).with(server).and_return(host_engine)
        allow(ExternalProxyConfigurator).to receive(:new).and_return(configurator)
        allow(engine).to receive(:domain_add).and_return(success: true, output: "")
        allow(engine).to receive(:ps_rebuild).and_return(success: true, output: "")
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

  describe "DELETE /api/services/:service_id/domains/:hostname" do
    let!(:domain) { create(:domain, service: service, hostname: "test.com") }

    it "destroys the domain" do
      delete "/api/services/#{service.id}/domains/test.com", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(service.domains.count).to eq(0)
    end

    it "returns 404 for non-existent domain" do
      delete "/api/services/#{service.id}/domains/missing.com", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
