require "rails_helper"

RSpec.describe CheckSslStatusJob do
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:service) { create(:service, project: project) }
  let!(:pending) { create(:domain, service: service, ssl: true, ssl_status: "pending", ssl_checked_at: nil) }
  let!(:stale) { create(:domain, service: service, ssl: true, ssl_status: "active", ssl_checked_at: 7.hours.ago) }
  let!(:fresh) { create(:domain, service: service, ssl: true, ssl_status: "active", ssl_checked_at: 1.hour.ago) }

  it "checks pending and stale certificates without touching fresh ones" do
    checker = double("SslStatusChecker")
    allow(SslStatusChecker).to receive(:new).and_return(checker)
    allow(HostEngine).to receive(:new).and_return(double("HostEngine"))
    expect(checker).to receive(:check).with(pending)
    expect(checker).to receive(:check).with(stale)
    expect(checker).not_to receive(:check).with(fresh)

    described_class.perform_now
  end
end
