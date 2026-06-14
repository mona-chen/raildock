require "rails_helper"

RSpec.describe ExternalProxyConfigurator do
  let(:server) do
    create(
      :server,
      proxy_mode: "external",
      external_proxy_network: "matrix_default",
      external_proxy_default_labels: { "traefik.constraint-label" => "matrix" }
    )
  end
  let(:service) do
    create(
      :service,
      project: create(:project, server: server),
      config: {
        "traefik" => {
          "labels" => {
            "traefik.http.routers.custom.priority" => "100"
          }
        }
      }
    )
  end
  let(:engine) { instance_double(DokkuEngine) }
  let(:host_engine) { instance_double(HostEngine) }

  before do
    create(:domain, service: service, hostname: "app.example.com", target_port: 5000)
    allow(host_engine).to receive(:docker_network_inspect).and_return(success: true, output: "{}")
    allow(host_engine).to receive(:run).and_return(success: true, output: "")
    allow(engine).to receive(:traefik_stop).and_return(success: true, output: "")
    allow(engine).to receive(:proxy_disable).and_return(success: true, output: "")
    allow(engine).to receive(:ports_clear).and_return(success: true, output: "")
    allow(engine).to receive(:docker_option_add).and_return(success: true, output: "")
    allow(engine).to receive(:docker_option_remove).and_return(success: true, output: "")
  end

  it "applies generated, global, and per-service labels to the web process" do
    result = described_class.new(service, engine, host_engine).apply!

    expect(result[:success]).to be(true)
    expect(engine).to have_received(:proxy_disable).with(service.dokku_app_name)
    expect(host_engine).to have_received(:run).with(
      a_string_including("traefik/#{service.dokku_app_name}/labels")
    ).once
    expect(engine).to have_received(:docker_option_add).with(
      service.dokku_app_name,
      "deploy",
      '--label "traefik.enable=true"',
      process: "web"
    )
    expect(engine).to have_received(:docker_option_add).with(
      service.dokku_app_name,
      "deploy",
      '--label "traefik.docker.network=matrix_default"',
      process: "web"
    )
  end

  it "replaces previously managed labels and includes domains added later" do
    described_class.new(service, engine, host_engine).apply!
    create(:domain, service: service, hostname: "api.example.com", target_port: 5000)

    described_class.new(service.reload, engine, host_engine).apply!

    expect(engine).to have_received(:docker_option_remove).at_least(:once)
    expect(engine).to have_received(:docker_option_add).with(
      service.dokku_app_name,
      "deploy",
      a_string_including('Host(\`api.example.com\`)'),
      process: "web"
    )
  end

  it "fails without mutating proxy settings when the network is missing" do
    allow(host_engine).to receive(:docker_network_inspect).and_return(success: false, output: "not found")

    result = described_class.new(service, engine, host_engine).apply!

    expect(result[:success]).to be(false)
    expect(result[:output]).to match(/matrix_default/)
    expect(engine).not_to have_received(:traefik_stop)
    expect(engine).not_to have_received(:proxy_disable)
    expect(engine).not_to have_received(:ports_clear)
  end
end
