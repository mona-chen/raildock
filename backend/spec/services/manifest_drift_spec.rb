require "rails_helper"

RSpec.describe ManifestDrift do
  let(:manifest) do
    <<~TOML
      [[services]]
      name = "web"
      category = "app"
      subtype = "web"
      builder = "nixpacks"
      port = 3000
      source = { type = "git", repo = "https://github.com/acme/store.git", branch = "main" }

      [[services]]
      name = "db"
      category = "database"
      subtype = "postgres"
      version = "16"
    TOML
  end

  let(:project) do
    create(:project, name: "Storefront", manifest_format: "raildock.toml", manifest_content: manifest)
  end

  let!(:web) do
    create(
      :service,
      project: project,
      name: "web",
      managed_by: :manifest,
      builder: "nixpacks",
      git_repo: "https://github.com/acme/store.git",
      branch: "main",
      port: 8080
    )
  end

  let!(:worker) do
    create(
      :service,
      project: project,
      name: "worker",
      managed_by: :manifest,
      git_repo: "https://github.com/acme/worker.git"
    )
  end

  let!(:cache) do
    create(:service, project: project, name: "cache", managed_by: :ui, git_repo: "https://github.com/acme/cache.git")
  end

  subject(:drift) do
    described_class.new(
      project,
      desired: ManifestParser.parse(project.manifest_content, filename: project.manifest_format)
    )
  end

  describe "#report" do
    it "groups drift per service with both the manifest and live values" do
      report = drift.report
      web_report = report[:services].find { |service| service[:name] == "web" }

      expect(report[:drift_detected]).to be(true)
      expect(web_report[:status]).to eq("drifted")
      expect(web_report[:mergeable]).to be(true)

      port = web_report[:changes].find { |change| change[:field] == "port" }
      expect(port).to include(manifest_value: 3000, live_value: 8080)
    end

    it "flags a service declared only in the manifest as missing from the host" do
      db_report = drift.report[:services].find { |service| service[:name] == "db" }

      expect(db_report).to include(status: "missing_from_host", mergeable: false)
      expect(db_report[:reason]).to be_present
    end

    it "flags live services absent from the manifest but leaves UI-managed services alone" do
      services = drift.report[:services]
      names = services.map { |service| service[:name] }

      expect(names).to include("worker")
      expect(names).not_to include("cache")
      expect(services.find { |service| service[:name] == "worker" }[:status]).to eq("missing_from_manifest")
    end

    it "summarizes the drift" do
      expect(drift.report[:summary]).to include(
        missing_from_manifest: 1,
        missing_from_host: 1,
        mergeable_services: 2
      )
    end
  end

  describe "#merged" do
    it "rewrites accepted services with live values and preserves the rest of the manifest" do
      result = drift.merged([ "web", "worker" ])
      reparsed = ManifestParser.parse(result[:content], filename: "raildock.toml")
      by_name = reparsed.services.index_by { |service| service[:name] }

      expect(result[:format]).to eq("raildock.toml")
      expect(result[:adopted]).to contain_exactly("web", "worker")
      expect(result[:skipped]).to be_empty

      # A service declared in the manifest but not deployed is never dropped.
      expect(by_name.keys).to contain_exactly("web", "db", "worker")
      expect(by_name["db"][:category]).to eq("database")
      expect(by_name["web"][:port]).to eq(8080)
      expect(by_name["worker"][:source][:repo]).to eq("https://github.com/acme/worker.git")
    end

    it "fetches every drifted field from live state, not just the reported one" do
      result = drift.merged([ "web" ])
      reparsed = ManifestParser.parse(result[:content], filename: "raildock.toml")
      web = reparsed.services.find { |service| service[:name] == "web" }

      expect(web[:restart_policy]).to eq("on-failure")
      expect(web[:restart_max_retries]).to eq(10)
    end

    it "reports non-mergeable requests as skipped instead of merging them" do
      result = drift.merged([ "db" ])

      expect(result[:adopted]).to be_empty
      expect(result[:skipped]).to eq([ "db" ])
    end

    it "writes back the live links of an adopted service" do
      ServiceLink.create!(from_service: worker, to_service: web)

      result = drift.merged([ "worker" ])
      reparsed = ManifestParser.parse(result[:content], filename: "raildock.toml")

      expect(reparsed.links.map { |link| [ link[:from], link[:to] ] }).to include([ "worker", "web" ])
    end

    it "merges every mergeable service when accept_all is set" do
      result = drift.merged([], accept_all: true)

      expect(result[:adopted]).to contain_exactly("web", "worker")
      expect(result[:skipped]).to be_empty
    end

    context "when the project uses a compatibility format" do
      let(:project) do
        create(
          :project,
          manifest_format: "railway.toml",
          manifest_content: "[build]\nbuilder = \"NIXPACKS\"\n"
        )
      end

      it "reports merge as unsupported and refuses to regenerate the file" do
        expect(drift).not_to be_supported
        expect(drift.merged([ "web" ], accept_all: true)).to be_nil
      end
    end
  end
end
