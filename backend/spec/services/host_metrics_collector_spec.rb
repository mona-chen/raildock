require "rails_helper"

RSpec.describe HostMetricsCollector do
  let(:server) { create(:server) }
  let(:engine) { instance_double(HostEngine) }
  let(:output) { "cpu 0.125\nmemory 42.5\ndisk 61\nload 0.3\nuptime_seconds 86400\nnetwork_rx 5000\nnetwork_tx 9000\n" }

  before do
    allow(HostEngine).to receive(:new).with(server).and_return(engine)
    allow(engine).to receive(:run).and_return(success: true, output: output)
  end

  it "preserves fractional CPU readings and caches samples across callers" do
    first = described_class.call(server)
    expect(first.data).to include("cpu" => 0.125, "memory" => 42.5, "available" => true)
    expect(described_class.call(server).id).to eq(first.id)
    expect(engine).to have_received(:run).once
  end

  it "records a failed reading instead of converting it to zero" do
    allow(engine).to receive(:run).and_return(success: false, output: "private connection details")
    expect(described_class.call(server).data).to eq("available" => false, "reason" => "Host collection failed")
  end

  it "rejects incomplete or non-finite readings" do
    allow(engine).to receive(:run).and_return(success: true, output: "cpu NaN\n")
    expect(described_class.call(server).data["available"]).to be(false)
  end

  it "does not collect when disabled" do
    SystemSetting.set!("metrics_hosts_enabled", "false")
    expect(described_class.call(server)).to be_nil
    expect(engine).not_to have_received(:run)
  end
end
