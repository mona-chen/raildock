require "rails_helper"

RSpec.describe ServiceMetric, type: :model do
  let!(:service) { create(:service) }

  describe "associations" do
    it "belongs to a service" do
      metric = create(:service_metric, service: service)
      expect(metric.service).to eq(service)
    end
  end

  describe ".since" do
    it "returns samples after the cutoff" do
      old = create(:service_metric, service: service, sampled_at: 2.hours.ago)
      new = create(:service_metric, service: service, sampled_at: 10.minutes.ago)

      result = ServiceMetric.since(1.hour.ago)
      expect(result).to include(new)
      expect(result).not_to include(old)
    end
  end

  describe ".prune_older_than!" do
    it "removes samples older than the cutoff and keeps fresh ones" do
      old = create(:service_metric, service: service, sampled_at: 40.days.ago)
      fresh = create(:service_metric, service: service, sampled_at: 1.day.ago)

      ServiceMetric.prune_older_than!

      expect(ServiceMetric.exists?(old.id)).to be(false)
      expect(ServiceMetric.exists?(fresh.id)).to be(true)
    end
  end

  describe "retention constant" do
    it "is 30 days" do
      expect(ServiceMetric::RETENTION).to eq(30.days)
    end
  end
end
