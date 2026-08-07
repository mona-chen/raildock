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
    allow(host_engine).to receive(:dokku_container_name).and_return(nil)
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

  it "prefers an explicit domain target_port over a stale detected_port" do
    service.update!(detected_port: 5000)
    service.domains.update_all(target_port: 3000)

    described_class.new(service, engine, host_engine).apply!

    expect(engine).to have_received(:docker_option_add).with(
      service.dokku_app_name,
      "deploy",
      a_string_including('traefik.http.services.'),
      process: "web"
    ) do |_, _, label, _|
      expect(label).to include('loadbalancer.server.port=3000')
    end
  end

  it "uses the actual listening port when the manifest port is stale" do
    service.update!(port: 5173, detected_port: 5000)
    service.domains.update_all(target_port: nil)
    allow(host_engine).to receive(:dokku_container_name).with(service.dokku_app_name).and_return("app.web.1")
    allow(host_engine).to receive(:run).with("docker exec app.web.1 sh -c 'cat /proc/net/tcp /proc/net/tcp6 2>/dev/null'")
      .and_return(success: true, output: "  0: 00000000:0BB8 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000 0 12345 1 0000000000000000 100 0 0 10 0\n")

    described_class.new(service, engine, host_engine).apply!

    expect(engine).to have_received(:docker_option_add).with(
      service.dokku_app_name,
      "deploy",
      a_string_including('traefik.http.services.'),
      process: "web"
    ) do |_, _, label, _|
      expect(label).to include('loadbalancer.server.url=http://app.web.1:3000')
      expect(label).not_to include('loadbalancer.server.port')
    end
  end

  it "pins the backend to the running container name when one is resolvable" do
    service.update!(detected_port: 3000)
    service.domains.update_all(target_port: 3000)
    allow(host_engine).to receive(:dokku_container_name).with(service.dokku_app_name).and_return("proj-web.web.1")

    described_class.new(service, engine, host_engine).apply!

    expect(engine).to have_received(:docker_option_add).with(
      service.dokku_app_name,
      "deploy",
      a_string_including('loadbalancer.server.url=http://proj-web.web.1:3000'),
      process: "web"
    )
  end

  it "falls back to a port label when the container is not yet running" do
    allow(host_engine).to receive(:dokku_container_name).and_return(nil)

    described_class.new(service, engine, host_engine).apply!

    expect(engine).to have_received(:docker_option_add).with(
      service.dokku_app_name,
      "deploy",
      a_string_including('loadbalancer.server.port=5000'),
      process: "web"
    )
    expect(engine).not_to have_received(:docker_option_add).with(
      service.dokku_app_name,
      "deploy",
      a_string_including('loadbalancer.server.url'),
      process: "web"
    )
  end
end
