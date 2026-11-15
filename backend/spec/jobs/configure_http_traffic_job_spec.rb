require "rails_helper"

RSpec.describe ConfigureHttpTrafficJob do
  let(:server) { create(:server, traffic_settings: { "enabled" => false, "setup_state" => "running" }) }

  it "enables collection only after a successful host setup" do
    allow_any_instance_of(HttpTrafficSetup).to receive(:apply).with("reviewed").and_return({ "path" => "/var/log/raildock-http/proxy/access.log" })
    expect(HttpTrafficCollector).to receive(:call).with(server)
    described_class.perform_now(server.id, "reviewed")
    expect(server.reload.traffic_settings).to include("enabled" => true, "setup_state" => "completed", "capture_paths" => false)
  end

  it "reports failed host setup without claiming collection was enabled" do
    allow_any_instance_of(HttpTrafficSetup).to receive(:apply).and_raise(HttpTrafficSetup::Error, "Original configuration restored")
    expect(HttpTrafficCollector).not_to receive(:call)
    described_class.perform_now(server.id, "reviewed")
    expect(server.reload.traffic_settings).to include("enabled" => false, "setup_state" => "failed", "setup_error" => "Original configuration restored")
  end
end
