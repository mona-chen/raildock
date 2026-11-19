require "rails_helper"

RSpec.describe AgentRateLimit do
  let(:organization) { create(:organization) }
  let(:user) { create(:user) }
  let(:token) { ApiToken.issue!(organization: organization, user: user, name: "agent", scopes: [ "read" ]) }
  let(:now) { Time.zone.parse("2026-01-01 12:00:00") }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  around do |example|
    previous = ENV["AGENT_RATE_LIMIT_PER_MINUTE"]
    ENV["AGENT_RATE_LIMIT_PER_MINUTE"] = "2"
    example.run
  ensure
    previous.nil? ? ENV.delete("AGENT_RATE_LIMIT_PER_MINUTE") : ENV["AGENT_RATE_LIMIT_PER_MINUTE"] = previous
  end

  before do
    allow(Rails).to receive(:cache).and_return(cache)
  end

  it "allows up to the limit, then reports how long to wait" do
    expect(described_class.retry_after(token, now: now)).to be_nil
    expect(described_class.retry_after(token, now: now)).to be_nil
    expect(described_class.retry_after(token, now: now)).to be_between(1, 60)
  end

  it "counts per token" do
    other = ApiToken.issue!(organization: organization, user: user, name: "other", scopes: [ "read" ])

    2.times { described_class.retry_after(token, now: now) }

    expect(described_class.retry_after(other, now: now)).to be_nil
  end

  it "resets in the next window" do
    3.times { described_class.retry_after(token, now: now) }

    expect(described_class.retry_after(token, now: now + 61.seconds)).to be_nil
  end

  it "treats a cache failure as unlimited instead of failing the request" do
    allow(Rails.cache).to receive(:increment).and_raise(StandardError, "cache down")

    expect(described_class.retry_after(token, now: now)).to be_nil
  end
end
