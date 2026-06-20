require "rails_helper"

RSpec.describe RealtimeBroadcaster do
  let(:service) { create(:service) }

  it "never lets cable failures escape into business operations" do
    allow(DeploymentsChannel).to receive(:broadcast_to).and_raise("cable unavailable")

    expect(described_class.deployment(service, { status: "building" })).to be(false)
  end
end
