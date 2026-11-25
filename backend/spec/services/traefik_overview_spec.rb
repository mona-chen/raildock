require "rails_helper"

RSpec.describe TraefikOverview do
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:service) { create(:service, project: project, name: "Web", dokku_app_name: "demo-web") }
  let!(:domain) { create(:domain, service: service, hostname: "app.example.com", ssl: true, ssl_status: "active", ssl_expires_at: 1.month.from_now) }
  let(:host) { double("HostEngine") }
  let(:engine) { double("DokkuEngine") }
  let(:inventory) do
    [
      { "ID" => "a" * 12, "Names" => "demo-web.web.1", "Image" => "nginx:alpine", "State" => "running", "Status" => "Up", "Ports" => "0.0.0.0:80->80/tcp", "Networks" => "proxy" },
      { "ID" => "b" * 12, "Names" => "traefik-traefik-1", "Image" => "traefik:v3.6", "State" => "running", "Status" => "Up", "Ports" => "0.0.0.0:443->443/tcp", "Networks" => "proxy" }
    ]
  end

  subject(:overview) { described_class.new(server, host_engine: host, engine: engine) }

  before do
    allow(host).to receive(:docker_container_inventory).and_return(success: true, output: inventory.map(&:to_json).join("\n"))
    allow(engine).to receive(:run).with("traefik:report --global --format json").and_return(
      success: true,
      output: {
        "image" => "traefik:v3.6",
        "http-entry-point" => "web",
        "https-entry-point" => "websecure",
        "letsencrypt-email" => "ops@example.com",
        "dns-provider-cf_api_key" => "must-not-leak"
      }.to_json
    )
  end

  it "combines proxy containers, intended routes and certificate state" do
    result = overview.call

    expect(result[:mode]).to eq("managed")
    expect(result[:containers].map { |container| container[:name] }).to include("traefik-traefik-1")
    expect(result[:routes].first).to include(
      hostname: "app.example.com",
      backend: "http://demo-web.web.1:5000",
      state: "active"
    )
    expect(result[:certificates].first).to include(hostname: "app.example.com", status: "active")
    expect(result[:settings]).to include(image: "traefik:v3.6", http_entrypoint: "web")
    expect(result[:settings].to_json).not_to include("must-not-leak")
  end

  it "reports proxy containers as read-only in external mode" do
    server.update!(proxy_mode: "external", external_proxy_network: "proxy")

    result = overview.call

    expect(result[:managed]).to be false
    expect(result[:settings]).to eq({})
    expect(engine).not_to have_received(:run)
    expect(result[:containers].length).to eq(1)
  end

  it "keeps managed apps on another proxy out of the Traefik route table" do
    service.update!(config: { "proxy" => { "enabled" => true, "proxyType" => "nginx" } })

    result = overview.call

    expect(result[:routes]).to be_empty
    expect(result[:certificates]).to be_empty
  end

  it "keeps routes visible when Docker inventory is unavailable" do
    allow(host).to receive(:docker_container_inventory).and_return(success: false, output: "SSH error")

    result = overview.call

    expect(result[:inventory_error]).to eq("SSH error")
    expect(result[:routes].first[:state]).to eq("unknown")
    expect(result[:routes].first[:running]).to be_nil
  end
end
