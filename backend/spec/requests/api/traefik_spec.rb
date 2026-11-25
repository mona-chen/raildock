require "rails_helper"

RSpec.describe "Server Traefik management", type: :request do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let!(:membership) { create(:organization_membership, organization: organization, user: user, role: :owner) }
  let(:server) { create(:server, organization: organization, proxy_mode: "managed") }
  let(:headers) { auth_headers(user).merge("X-Organization-ID" => organization.id.to_s) }
  let(:overview) { double("TraefikOverview", call: { mode: "managed", managed: true, routes: [], certificates: [], warnings: [], containers: [], settings: {} }) }

  before do
    allow(TraefikOverview).to receive(:new).and_return(overview)
  end

  it "returns the read-only proxy overview" do
    get "/api/servers/#{server.id}/traefik", headers: headers

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["mode"]).to eq("managed")
  end

  it "reads redacted logs" do
    logs = double("TraefikLogs", call: { success: true, output: "line", lines: 200 })
    allow(TraefikLogs).to receive(:new).and_return(logs)

    get "/api/servers/#{server.id}/traefik/logs", headers: headers

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["output"]).to eq("line")
  end

  it "requires the exact server name before stopping the managed proxy" do
    expect(DokkuEngine).not_to receive(:new)

    post "/api/servers/#{server.id}/traefik", params: { operation: "stop", confirmation: "wrong" }, headers: headers

    expect(response).to have_http_status(:precondition_required)
    expect(JSON.parse(response.body)["code"]).to eq("confirmation_required")
  end

  it "starts the managed proxy" do
    engine = double("DokkuEngine", traefik_start: { success: true, output: "started" })
    allow(DokkuEngine).to receive(:new).with(server).and_return(engine)

    post "/api/servers/#{server.id}/traefik", params: { operation: "start" }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["operation"]).to eq("start")
  end

  it "refuses to start an external proxy" do
    server.update!(proxy_mode: "external", external_proxy_network: "proxy")
    expect(DokkuEngine).not_to receive(:new)

    post "/api/servers/#{server.id}/traefik", params: { operation: "start" }, headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["code"]).to eq("external_proxy_read_only")
  end

  it "queues an external routing check" do
    server.update!(proxy_mode: "external", external_proxy_network: "proxy")
    expect(ProxyDriftCheckJob).to receive(:perform_later).with(server.id)

    post "/api/servers/#{server.id}/traefik", params: { operation: "check" }, headers: headers

    expect(response).to have_http_status(:accepted)
  end
end
