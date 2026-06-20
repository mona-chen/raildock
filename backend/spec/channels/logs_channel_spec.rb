require "rails_helper"

RSpec.describe LogsChannel, type: :channel do
  let(:user) { create(:user) }
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:service) { create(:service, project: project) }

  before do
    stub_connection current_user: user
    described_class.active_subscribers.clear
    described_class.active_log_streams.clear
    described_class.active_log_threads.clear
  end

  describe "subscriber tracking" do
    it "keeps the shared log tail alive until the last subscriber leaves" do
      expect(described_class.add_subscriber(service.id, "tab-1")).to be(true)
      expect(described_class.add_subscriber(service.id, "tab-2")).to be(false)
      expect(described_class.remove_subscriber(service.id, "tab-1")).to be(false)
      expect(described_class.remove_subscriber(service.id, "tab-2")).to be(true)
    end
  end

  describe "#subscribed" do
    it "confirms subscription and streams for the service" do
      # Prevent the background thread from spawning and attempting SSH
      allow(Thread).to receive(:new).and_return(double("thread", kill: true))

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

    it "starts a background thread to tail logs" do
      thread_double = double("thread", kill: true)
      expect(Thread).to receive(:new).and_return(thread_double)

      subscribe(service_id: service.id)
    end
  end

  describe "#unsubscribed" do
    it "kills the background thread" do
      thread_double = double("thread")
      allow(Thread).to receive(:new).and_return(thread_double)

      subscribe(service_id: service.id)

      expect(thread_double).to receive(:kill)
      subscription.unsubscribe_from_channel
    end
  end
end
