require "rails_helper"
RSpec.describe HttpTrafficCollector do
  let(:server) { create(:server, traffic_settings: { "enabled" => true, "path" => "/var/log/access.log", "format" => "caddy" }) }
  let(:engine) { instance_double(HostEngine) }
  before { allow(HostEngine).to receive(:new).with(server).and_return(engine) }
  it "commits offsets and minute/hour aggregates together and coalesces repeated reads" do
    payload = { cursor: { inode: "1:2", offset: 100 }, backlog_bytes: 0, invalid_lines: 0, groups: [ { at: Time.current.beginning_of_minute.to_i, service_id: "unmapped", requests: 2, bandwidth: 400, histogram: [ 0, 2 ], paths: {} } ] }
    allow(engine).to receive(:run).and_return(success: true, output: payload.to_json)
    described_class.call(server)
    described_class.call(server)
    expect(engine).to have_received(:run).once
    expect(server.reload.traffic_cursor["offset"]).to eq(100)
    expect(server.http_traffic_buckets.count).to eq(2)
    expect(server.http_traffic_buckets.pluck(:resolution)).to contain_exactly("minute", "hour")
    expect(server.http_traffic_buckets.first.data["unmapped"]["requests"]).to eq(2)
  end
  it "does not advance the cursor on collection failure" do
    server.update!(traffic_cursor: { inode: "1:2", offset: 100 })
    allow(engine).to receive(:run).and_return(success: false, output: "private host details")
    described_class.call(server)
    expect(server.reload.traffic_cursor).to include("offset" => 100, "error" => "Collection failed. Check Python 3, the log file and JSON format.")
    expect(server.http_traffic_buckets.count).to eq(0)
  end
  it "does no SSH work when collection is disabled" do
    server.update!(traffic_settings: { enabled: false })
    expect(engine).not_to receive(:run)
    described_class.call(server)
  end
end
