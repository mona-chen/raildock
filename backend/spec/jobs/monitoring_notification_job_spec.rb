require "rails_helper"
RSpec.describe MonitoringNotificationJob do
  let(:server) { create(:server) }
  let(:incident) { server.monitoring_incidents.create!(signal: "cpu", state: "firing", started_at: Time.current, last_seen_at: Time.current, message: "CPU pressure", delivery_status: "queued") }
  before { server.organization.update!(notification_settings: { enabled: true, email: true }) }
  it "does not report delivery when SMTP is unconfigured" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SMTP_ADDRESS").and_return(nil)
    described_class.new.perform(incident.id, "firing")
    expect(incident.reload.delivery_status).to eq("smtp_unconfigured")
  end
  it "includes configured team destinations in alert delivery" do
    server.organization.update!(notification_settings: { enabled: true, email: true, email_destinations: [ "ops@example.test" ] })
    SystemSetting.set!("smtp_enabled", "true")
    SystemSetting.set!("smtp_address", "smtp.example.test")
    allow(SmtpService).to receive(:apply_from_db!)
    allow(ActionMailer::Base).to receive(:delivery_method).and_return(:smtp)
    expect(MonitoringMailer).to receive(:incident).with(incident: incident, recipients: [ server.organization.owner.email, "ops@example.test" ]).and_return(double(deliver_now: true))
    described_class.new.perform(incident.id, "firing")
    expect(incident.reload.delivery_status).to eq("delivered")
  end
  it "sends only to this organization's admins and does not resend delivered alerts" do
    SystemSetting.set!("smtp_enabled", "true")
    SystemSetting.set!("smtp_address", "smtp.example.test")
    allow(SmtpService).to receive(:apply_from_db!)
    allow(ActionMailer::Base).to receive(:delivery_method).and_return(:smtp)
    delivery = double(deliver_now: true)
    expect(MonitoringMailer).to receive(:incident).with(incident: incident, recipients: [ server.organization.owner.email ]).once.and_return(delivery)
    described_class.new.perform(incident.id, "firing")
    described_class.new.perform(incident.id, "firing")
    expect(incident.reload.delivery_status).to eq("delivered")
  end
end
