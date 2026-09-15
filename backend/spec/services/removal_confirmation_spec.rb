require "rails_helper"

RSpec.describe RemovalConfirmation do
  include ActiveSupport::Testing::TimeHelpers

  let(:project) { create(:project) }
  let(:digest) { described_class.digest_for("name = \"shop\"\n") }

  it "issues a token that authorises exactly the previewed removals" do
    token = described_class.issue(project: project, digest: digest, removals: %w[worker cron])

    expect(
      described_class.verify!(token: token, project: project, digest: digest, removals: %w[cron worker])
    ).to eq(%w[cron worker])
  end

  it "rejects a token issued for a different manifest revision" do
    token = described_class.issue(project: project, digest: digest, removals: %w[worker])

    expect {
      described_class.verify!(token: token, project: project, digest: described_class.digest_for("changed"), removals: %w[worker])
    }.to raise_error(described_class::InvalidConfirmation, /manifest changed/)
  end

  it "rejects a token that does not cover every service about to be destroyed" do
    token = described_class.issue(project: project, digest: digest, removals: %w[worker])

    expect {
      described_class.verify!(token: token, project: project, digest: digest, removals: %w[worker database])
    }.to raise_error(described_class::InvalidConfirmation, /list of services to destroy changed/)
  end

  it "rejects a token issued for another project" do
    token = described_class.issue(project: create(:project), digest: digest, removals: %w[worker])

    expect {
      described_class.verify!(token: token, project: project, digest: digest, removals: %w[worker])
    }.to raise_error(described_class::InvalidConfirmation, /does not belong to this project/)
  end

  it "rejects missing and forged tokens" do
    expect {
      described_class.verify!(token: nil, project: project, digest: digest, removals: %w[worker])
    }.to raise_error(described_class::InvalidConfirmation, /required/)

    expect {
      described_class.verify!(token: "not-a-real-token", project: project, digest: digest, removals: %w[worker])
    }.to raise_error(described_class::InvalidConfirmation, /invalid or expired/)
  end

  it "rejects an expired token" do
    token = travel_to(2.hours.ago) do
      described_class.issue(project: project, digest: digest, removals: %w[worker])
    end

    expect {
      described_class.verify!(token: token, project: project, digest: digest, removals: %w[worker])
    }.to raise_error(described_class::InvalidConfirmation)
  end
end
