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
    allow(engine).to receive(:docker_options_report).and_return(success: true, output: "")
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

  it "removes a stale backend port label before applying the resolved url label" do
    allow(host_engine).to receive(:dokku_container_name).and_return("app.web.1")
    backend_port = "traefik.http.services.#{service.dokku_app_name}-web.loadbalancer.server.port=5000"
    allow(engine).to receive(:docker_options_report).and_return(
      success: true,
      output: "--label traefik.enable=true --label '#{backend_port}'"
    )

    described_class.new(service, engine, host_engine).apply!

    expect(engine).to have_received(:docker_option_remove).with(
      service.dokku_app_name,
      "deploy",
      %(--label "#{backend_port}"),
      process: "web"
    )
    expect(engine).not_to have_received(:docker_option_remove).with(
      service.dokku_app_name,
      "deploy",
      '--label "traefik.enable=true"',
      process: "web"
    )
  end

  it "does not re-apply labels that already match the desired state" do
    allow(host_engine).to receive(:dokku_container_name).and_return("app.web.1")

    # First apply captures exactly what RailDock writes.
    written = []
    allow(engine).to receive(:docker_option_add) do |_app, _phase, option, process:|
      written << option
      { success: true, output: "" }
    end

    described_class.new(service, engine, host_engine).apply!
    expect(written).not_to be_empty

    # Second apply with the host already reporting those labels changes nothing.
    allow(engine).to receive(:docker_options_report).and_return(
      success: true,
      output: written.join(" ")
    )
    written.clear

    result = described_class.new(service.reload, engine, host_engine).apply!

    expect(result[:success]).to be(true)
    expect(written).to be_empty
    expect(engine).not_to have_received(:docker_option_remove)
  end

  it "fails loudly when a stale label cannot be removed" do
    stale_url = "traefik.http.services.#{service.dokku_app_name}-web.loadbalancer.server.url=http://stale.web.1:9999"
    allow(engine).to receive(:docker_options_report).and_return(
      success: true,
      output: "--label '#{stale_url}'"
    )
    allow(engine).to receive(:docker_option_remove).and_return(success: false, output: "boom")

    result = described_class.new(service, engine, host_engine).apply!

    expect(result[:success]).to be(false)
    expect(result[:output]).to include("remove label")
  end

  it "fails loudly when a desired label cannot be added" do
    allow(engine).to receive(:docker_option_add).and_return(success: false, output: "boom")

    result = described_class.new(service, engine, host_engine).apply!

    expect(result[:success]).to be(false)
    expect(result[:output]).to include("add label")
  end

  describe "#routing_problems" do
    let(:configurator) { described_class.new(service, engine, host_engine) }
    let(:backend) { "traefik.http.services.#{service.dokku_app_name}-web.loadbalancer.server." }
    let(:desired) do
      allow(host_engine).to receive(:dokku_container_name).and_return("app.web.1")
      configurator.apply!
      service.reload.config.fetch(ExternalProxyConfigurator::MANAGED_LABELS_KEY)
    end

    it "reports nothing when the container serves the desired labels" do
      expect(configurator.routing_problems(desired)).to eq({})
    end

    it "ignores a container still on the port label instead of the url label" do
      actual = desired.except("#{backend}url").merge("#{backend}port" => "5000")

      expect(configurator.routing_problems(actual)).to eq({})
    end

    it "flags a service that defines both the port and url backend" do
      actual = desired.merge("#{backend}port" => "5000")

      expect(configurator.routing_problems(actual)[:conflicting_backend]).to eq(
        [ "#{backend}port", "#{backend}url" ]
      )
    end

    it "flags a service whose routers have no backend" do
      actual = desired.except("#{backend}url")

      expect(configurator.routing_problems(actual)[:missing_backend]).to eq([ backend ])
    end

    it "flags a desired host rule the container is not routing" do
      actual = desired.reject { |key, _| key.end_with?(".rule") }

      expect(configurator.routing_problems(actual)[:missing_routers]).not_to be_empty
    end
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
