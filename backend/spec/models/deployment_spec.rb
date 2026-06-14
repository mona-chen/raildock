require 'rails_helper'

RSpec.describe Deployment, type: :model do
  describe "validations" do
    it "is valid with recognized statuses" do
      %w[pending building deploying succeeded failed cancelled].each do |status|
        expect(build(:deployment, status: status)).to be_valid
      end
    end

    it "raises ArgumentError with an unrecognized status" do
      expect {
        build(:deployment, status: "unknown")
      }.to raise_error(ArgumentError, "'unknown' is not a valid status")
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:service) }
  end

  describe "enums" do
    it "defines status enum with correct values" do
      expect(described_class.statuses.keys).to contain_exactly("pending", "building", "deploying", "succeeded", "failed", "cancelled")
    end
  end

  describe "#duration" do
    it "returns nil when started_at is missing" do
      deployment = build(:deployment, started_at: nil, completed_at: Time.current)
      expect(deployment.duration).to be_nil
    end

    it "returns nil when completed_at is missing" do
      deployment = build(:deployment, started_at: 1.hour.ago, completed_at: nil)
      expect(deployment.duration).to be_nil
    end

    it "returns nil when both timestamps are missing" do
      deployment = build(:deployment, started_at: nil, completed_at: nil)
      expect(deployment.duration).to be_nil
    end

    it "returns the difference in seconds when both timestamps are present" do
      started = Time.current - 300
      completed = Time.current
      deployment = build(:deployment, started_at: started, completed_at: completed)
      expect(deployment.duration).to be_within(1).of(300)
    end
  end

  describe "#cancel!" do
    before do
      allow(DeploymentsChannel).to receive(:broadcast_to)
    end

    it "atomically cancels an active deployment and restores a previously running service" do
      service = create(:service, status: :deploying)
      create(:deployment, service: service, status: :succeeded)
      deployment = create(:deployment, service: service, status: :pending, started_at: nil)

      expect(deployment.cancel!).to be(true)

      expect(deployment.reload).to be_cancelled
      expect(service.reload).to be_running
    end

    it "returns false when another caller already completed the deployment" do
      deployment = create(:deployment, status: :succeeded)

      expect(deployment.cancel!).to be(false)
    end
  end
end
