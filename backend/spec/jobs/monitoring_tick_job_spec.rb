require "rails_helper"
RSpec.describe MonitoringTickJob do
  it "prunes minute and hourly history independently even when collection is disabled" do
    server = create(:server, traffic_settings: { enabled: false, retention_days: 7 })
    minute = server.http_traffic_buckets.create!(bucket_at: 3.days.ago, resolution: "minute")
    hour = server.http_traffic_buckets.create!(bucket_at: 3.days.ago, resolution: "hour")
    expired = server.http_traffic_buckets.create!(bucket_at: 8.days.ago, resolution: "hour")
    described_class.perform_now
    expect(HttpTrafficBucket.exists?(minute.id)).to be(false)
    expect(HttpTrafficBucket.exists?(hour.id)).to be(true)
    expect(HttpTrafficBucket.exists?(expired.id)).to be(false)
  end
end
