require "rails_helper"

RSpec.describe ProxyDriftCheckJob, type: :job do
  let(:server) do
    create(:server, proxy_mode: "external", external_proxy_network: "traefik")
  end
  let(:project) { create(:project, server: server) }
  let(:service) { create(:service, project: project) }
  let(:engine) { instance_double(DokkuEngine) }
  let(:host_engine) { instance_double(HostEngine) }
  let(:configurator) { instance_double(ExternalProxyConfigurator) }

  before do
    create(:domain, service: service, hostname: "app.example.com", target_port: 5000)
    allow(DokkuEngine).to receive(:new).with(server).and_return(engine)
    allow(HostEngine).to receive(:new).with(server).and_return(host_engine)
    allow(host_engine).to receive(:dokku_container_name).and_return("app.web.1")
    allow(host_engine).to receive(:container_labels).and_return({ "traefik.enable" => "true" })
    allow(ExternalProxyConfigurator).to receive(:new).and_return(configurator)
  end

  it "records a warning event when the container labels drift" do
    allow(configurator).to receive(:drift).and_return(
      missing: { "traefik.enable" => "true" },
      stale: {}
    )

    result = described_class.perform_now

    expect(result[:checked]).to eq(1)
    expect(result[:drifted]).to eq(1)
    event = ActivityEvent.where(action: "warning").last
    expect(event).to be_present
    expect(event.service_name).to eq(service.name)
    expect(event.message).to include("Proxy configuration drift detected")
  end

  it "does nothing when the container matches the desired labels" do
    allow(configurator).to receive(:drift).and_return(missing: {}, stale: {})

    result = described_class.perform_now

    expect(result[:drifted]).to eq(0)
    expect(ActivityEvent.where(action: "warning")).to be_empty
  end

  it "suppresses repeat warnings for the same service within the window" do
    allow(configurator).to receive(:drift).and_return(
      missing: { "traefik.enable" => "true" },
      stale: {}
    )

    2.times { described_class.perform_now }

    expect(ActivityEvent.where(action: "warning").count).to eq(1)
  end

  it "skips services whose container is not running" do
    allow(host_engine).to receive(:dokku_container_name).and_return(nil)

    result = described_class.perform_now

    expect(result[:checked]).to eq(0)
    expect(ExternalProxyConfigurator).not_to have_received(:new)
  end
end
