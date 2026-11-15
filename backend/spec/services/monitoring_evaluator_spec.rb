require "rails_helper"
RSpec.describe MonitoringEvaluator do
  include ActiveSupport::Testing::TimeHelpers
  let(:server) { create(:server) }
  before do
    server.organization.update!(notification_settings: { "enabled" => true, "window_minutes" => 1 })
    SystemSetting.set!("metrics_services_enabled", "false")
  end
  it "requires sustained pressure, deduplicates and resolves after hysteresis" do
    start = Time.current.change(sec: 0)
    travel_to(start) do
      server.server_metrics.create!(sampled_at: Time.current, data: { available: true, cpu: 95, memory: 40, disk: 40 })
      described_class.call(server)
      expect(server.monitoring_incidents.find_by(signal: "cpu").state).to eq("pending")
    end
    travel_to(start + 1.minute) do
      server.server_metrics.create!(sampled_at: Time.current, data: { available: true, cpu: 95, memory: 40, disk: 40 })
      described_class.call(server)
      described_class.call(server)
      expect(server.monitoring_incidents.active.count).to eq(1)
    end
    travel_to(start + 2.minutes) do
      server.server_metrics.create!(sampled_at: Time.current, data: { available: true, cpu: 86, memory: 40, disk: 40 })
      described_class.call(server)
      expect(server.monitoring_incidents.active.count).to eq(1)
    end
    travel_to(start + 3.minutes) do
      server.server_metrics.create!(sampled_at: Time.current, data: { available: true, cpu: 50, memory: 40, disk: 40 })
      described_class.call(server)
      expect(server.monitoring_incidents.active.count).to eq(0)
      expect(server.monitoring_incidents.find_by(signal: "cpu").state).to eq("resolved")
    end
  end
  it "does not page about delayed replayed HTTP traffic" do
    server.update!(traffic_settings: { enabled: true }, traffic_cursor: { checked_at: Time.current.iso8601, backlog_bytes: 500 })
    server.http_traffic_buckets.create!(bucket_at: Time.current.beginning_of_minute - 1.minute, data: { "unmapped" => { "requests" => 5000 } })
    described_class.call(server)
    expect(server.monitoring_incidents.where(signal: "requests_per_minute")).to be_empty
  end
  it "does not create incidents when monitoring is disabled" do
    server.organization.update!(notification_settings: { enabled: false })
    expect { described_class.call(server) }.not_to change(MonitoringIncident, :count)
  end
end
