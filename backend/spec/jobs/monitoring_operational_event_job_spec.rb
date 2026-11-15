require "rails_helper"
RSpec.describe MonitoringOperationalEventJob do
  it "records deployment failure once and recovery when the next deploy succeeds" do
    service = create(:service)
    server = service.project.server
    server.organization.update!(notification_settings: { enabled: true })
    deployment = create(:deployment, service: service, status: "failed")
    described_class.new.perform("deployment", deployment.id)
    described_class.new.perform("deployment", deployment.id)
    expect(server.monitoring_incidents.active.count).to eq(1)
    success = create(:deployment, service: service, status: "succeeded")
    described_class.new.perform("deployment", success.id)
    expect(server.monitoring_incidents.active.count).to eq(0)
  end
end
