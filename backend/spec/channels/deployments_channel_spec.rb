require "rails_helper"

RSpec.describe DeploymentsChannel, type: :channel do
  let(:user) { create(:user) }
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:service) { create(:service, project: project) }

  before do
    stub_connection current_user: user
  end

  describe "#subscribed" do
    it "confirms subscription and streams for the service" do
      subscribe(service_id: service.id)

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_for(service)
    end

    it "rejects another user's personal project" do
      personal_project = create(:project, user: create(:user, admin: false))
      personal_service = create(:service, project: personal_project)
      stub_connection current_user: create(:user, admin: false)

      subscribe(service_id: personal_service.id)

      expect(subscription).to be_rejected
    end
  end

  describe "#unsubscribed" do
    it "does not raise an error" do
      subscribe(service_id: service.id)
      expect { subscription.unsubscribe_from_channel }.not_to raise_error
    end
  end
end
