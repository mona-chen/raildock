require "rails_helper"

RSpec.describe NetworkFlowCollector do
  include ActiveSupport::Testing::TimeHelpers
  let(:server) { create(:server, network_flow_settings: { "enabled" => true, "retention_days" => 0 }) }
  let(:project) { create(:project, server: server) }
  let!(:link) { ServiceLink.create!(from_service: create(:service, project: project), to_service: create(:service, project: project)) }
  let(:data) { { "sampled_at" => Time.current.iso8601, "links" => [ { "id" => link.id.to_s, "state" => "sampled", "sent_bytes" => 100, "received_bytes" => 200, "connections" => 1, "window_seconds" => 10 } ] } }

  it "coalesces clients and keeps live-only collection out of historical storage" do
    expect_any_instance_of(HostEngine).to receive(:run).once.and_return(success: true, output: data.to_json)
    2.times { described_class.call(server) }
    expect(server.reload.network_flow_snapshot["links"].first["last_activity_at"]).to eq(data["sampled_at"])
    expect(NetworkFlowSample.where(server: server)).to be_empty
  end

  it "never invokes SSH when collection is disabled" do
    server.update!(network_flow_settings: { "enabled" => false })
    expect(HostEngine).not_to receive(:new)
    described_class.call(server)
  end

  it "prunes retained history even when collection has been disabled" do
    NetworkFlowSample.create!(server: server, service_link: link, sampled_at: 2.days.ago, window_seconds: 60)
    server.update!(network_flow_settings: { "enabled" => false, "retention_days" => 1 })
    described_class.prune(server)
    expect(NetworkFlowSample.where(server: server)).to be_empty
  end
  it "rolls up samples within a minute instead of storing every canvas poll" do
    server.update!(network_flow_settings: { "enabled" => true, "retention_days" => 1 })
    allow_any_instance_of(HostEngine).to receive(:run) { { success: true, output: data.merge("sampled_at" => Time.current.iso8601).to_json } }
    travel_to(Time.current.change(sec: 1)) do
      described_class.call(server)
      travel 11.seconds
      described_class.call(server)
    end
    expect(NetworkFlowSample.where(server: server).count).to eq(1)
    expect(NetworkFlowSample.find_by!(server: server).sent_bytes).to eq(200)
  end
  it "can persist a sample when SSH stages an unpersisted first-connection host key" do
    allow_any_instance_of(HostEngine).to receive(:run) do
      server.host_key = "synthetic-first-connection-key"
      { success: true, output: data.to_json }
    end
    described_class.call(server)
    expect(server.reload.network_flow_snapshot["links"].first["sent_bytes"]).to eq(100)
  end
end
