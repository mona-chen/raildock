require "rails_helper"

RSpec.describe DokkuCapabilities do
  let(:server) { instance_double(Server, dokku_version: "0.38.34") }
  let(:engine) { instance_double(DokkuEngine, server: server) }

  it "reads installed plugin namespaces from the 0.38 help summary" do
    allow(engine).to receive(:run).with("help").and_return(
      success: true,
      output: <<~HELP
        Usage: dokku COMMAND
            app-json                 Manage app-json settings for an app
            apps                     Manage apps
            builds                   Manage running and historical builds
            cron                     Manage scheduled cron tasks
            logs                     Manage log output
            registry                 Manage registry settings for an app
            resource                 Manage resource settings for an app
            version                  Print dokku's version
      HELP
    )

    capabilities = described_class.new(engine).read

    expect(capabilities[:version]).to eq("0.38.34")
    expect(capabilities[:namespaces]).to include("apps", "builds", "cron", "logs", "registry", "resource", "version")
    expect(capabilities[:features]).to include("builds" => true, "cron" => true, "resource" => true, "registry" => true, "logs" => true, "maintenance" => false)
  end

  it "reads namespace prefixes from a fully-qualified command list" do
    allow(engine).to receive(:run).with("help").and_return(
      success: true,
      output: "    cron:list <app>          List scheduled cron tasks\n    resource:report <app>    Display resources\n"
    )

    capabilities = described_class.new(engine).read

    expect(capabilities[:features]).to include("cron" => true, "resource" => true, "builds" => false)
  end

  it "reports a host that cannot answer help" do
    allow(engine).to receive(:run).with("help").and_return(success: false, output: "denied")

    expect { described_class.new(engine).read }.to raise_error(ServiceSettingsSync::ApplyError, /capabilities/)
  end
end
