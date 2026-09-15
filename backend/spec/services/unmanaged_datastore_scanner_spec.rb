require "rails_helper"

RSpec.describe UnmanagedDatastoreScanner do
  let(:organization) { create(:organization) }
  let(:server) { create(:server, organization: organization) }
  let(:engine) { instance_double(DokkuEngine) }
  let(:scanner) { described_class.new(server, engine: engine) }

  let(:plugin_list) do
    <<~OUTPUT
      00_dokku-standard    0.38.1 enabled    dokku core standard plugin
      postgres             1.40.6 enabled    dokku postgres service plugin
      redis                1.40.6 enabled    dokku redis service plugin
      mysql                1.44.3 disabled   dokku mysql service plugin
    OUTPUT
  end

  before do
    allow(engine).to receive(:run).with("plugin:list").and_return(success: true, output: plugin_list)
    allow(engine).to receive(:run).with("postgres:list")
      .and_return(success: true, output: "=====> Postgres services\nmanaged-db\norphan-db\n")
    allow(engine).to receive(:run).with("redis:list")
      .and_return(success: true, output: "=====> Redis services\norphan-cache\n")
    allow(engine).to receive(:run).with("postgres:info orphan-db")
      .and_return(success: true, output: "       Status:              running\n")
    allow(engine).to receive(:run).with("postgres:links orphan-db")
      .and_return(success: true, output: "tween-jean-646e2ba9\n")
    allow(engine).to receive(:run).with("redis:info orphan-cache")
      .and_return(success: true, output: "       Status:              running\n")
    allow(engine).to receive(:run).with("redis:links orphan-cache")
      .and_return(success: true, output: "")

    # Already tracked by RailDock, so it must never show up as unmanaged.
    create(:service, :database, project: create(:project, server: server), dokku_app_name: "managed-db")
  end

  it "returns datastores that have no Service record" do
    result = scanner.scan

    expect(result[:success]).to be true
    expect(result[:resources].map { |resource| resource[:name] }).to contain_exactly("orphan-db", "orphan-cache")
  end

  it "reports the subtype, service type, status, and linked apps of each resource" do
    resource = scanner.scan[:resources].find { |candidate| candidate[:name] == "orphan-db" }

    expect(resource).to include(
      subtype: "postgres",
      service_type: "database",
      status: "running",
      linked_apps: [ "tween-jean-646e2ba9" ]
    )
  end

  it "classifies a linked cache as a cache service" do
    resource = scanner.scan[:resources].find { |candidate| candidate[:name] == "orphan-cache" }

    expect(resource).to include(subtype: "redis", service_type: "cache")
  end

  it "never queries a plugin Dokku has not enabled" do
    # Invoking a service plugin that is not installed makes Dokku install it, so
    # the disabled mysql plugin must not be touched.
    expect(engine).not_to receive(:run).with("mysql:list")

    scanner.scan
  end

  context "when a plugin backs more than one subtype" do
    let(:plugin_list) do
      <<~OUTPUT
        mysql                1.44.3 enabled    dokku mysql service plugin
      OUTPUT
    end

    before do
      allow(engine).to receive(:run).with("mysql:list")
        .and_return(success: true, output: "=====> Mysql services\nlegacy-db\n")
      allow(engine).to receive(:run).with("mysql:info legacy-db")
        .and_return(success: true, output: "       Status:              running\n")
      allow(engine).to receive(:run).with("mysql:links legacy-db").and_return(success: true, output: "")
    end

    it "lists the plugin once and attributes names to the namespace subtype" do
      resources = scanner.scan[:resources]

      expect(resources.map { |resource| resource[:name] }).to eq([ "legacy-db" ])
      expect(resources.first[:subtype]).to eq("mysql")
    end
  end

  it "keeps scanning when one plugin fails" do
    allow(engine).to receive(:run).with("postgres:list").and_return(success: false, output: "plugin exploded")

    result = scanner.scan

    expect(result[:success]).to be true
    expect(result[:resources].map { |resource| resource[:name] }).to eq([ "orphan-cache" ])
    expect(result[:errors].first).to include("postgres:list failed")
  end

  it "fails the scan when the plugin list cannot be read" do
    allow(engine).to receive(:run).with("plugin:list").and_return(success: false, output: "ssh refused")

    result = scanner.scan

    expect(result[:success]).to be false
    expect(result[:error]).to include("plugin list")
  end

  it "ignores a name already claimed by a service on another server" do
    create(:service, :database, project: create(:project, server: server), dokku_app_name: "orphan-cache")

    expect(scanner.scan[:resources].map { |resource| resource[:name] }).to eq([ "orphan-db" ])
  end
end
