require "rails_helper"

RSpec.describe ManagedAppJson do
  let(:service) { build(:service, port: "4000", config: config) }
  subject(:declaration) { described_class.new(service, double("Host")).declaration }

  context "with UI lifecycle settings" do
    let(:config) do
      { "checks" => { "path" => "/ready", "timeout" => 9, "attempts" => 4 },
        "cron" => [ { "schedule" => "@daily", "command" => "bin/cleanup" } ],
        "scripts" => { "predeploy" => "bin/migrate", "postdeploy" => "bin/warm" } }
    end

    it "declares checks, cron and release scripts in their native homes" do
      expect(declaration.dig("healthchecks", "web", 0)).to include("type" => "startup", "path" => "/ready", "port" => 4000, "timeout" => 9)
      expect(declaration["cron"]).to eq(config["cron"])
      expect(declaration["scripts"]).to eq(config["scripts"])
    end
  end

  context "with repository-owned scripts" do
    let(:config) { { "scripts" => { "source" => "repository", "format" => "app.json", "predeploy" => "bin/migrate" } } }
    it("leaves their execution to the original repository declaration") { expect(declaration).not_to have_key("scripts") }
  end

  context "with disabled checks and explicitly removed cron" do
    let(:config) { { "checks" => { "enabled" => false, "path" => "/ready" }, "cron" => [] } }
    it "clears cron without enabling a health endpoint" do
      expect(declaration).to include("cron" => [])
      expect(declaration).to include("healthchecks" => { "web" => [] })
    end
  end

  context "without any lifecycle settings" do
    let(:config) { {} }
    it "does not claim ownership of repository checks or scripts" do
      expect(declaration).not_to have_key("healthchecks")
      expect(declaration).not_to have_key("scripts")
    end
  end
end
