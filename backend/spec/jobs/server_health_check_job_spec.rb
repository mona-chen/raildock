require "rails_helper"

RSpec.describe ServerHealthCheckJob do
  let!(:server) { create(:server, status: :error, ssh_port: 2222, host_key: "ssh-ed25519 AAAAPINNED") }
  let(:session) { double("ssh") }

  it "runs on the maintenance queue" do
    expect(described_class.queue_name).to eq("maintenance")
  end

  it "is scheduled in recurring.yml on the maintenance queue" do
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)
    entry = recurring.dig("production", "server_health_check")
    expect(entry).to include("class" => "ServerHealthCheckJob", "queue" => "maintenance")
  end

  it "marks a reachable server connected, on its SSH port, without touching the pinned key" do
    expect(Net::SSH).to receive(:start).with(server.host, "dokku", hash_including(port: 2222, timeout: 10)).and_yield(session)
    allow(session).to receive(:exec!).with("version").and_return("dokku version 0.38.1\n")

    described_class.perform_now

    server.reload
    expect(server.status).to eq("connected")
    expect(server.status_checked_at).to be_present
    expect(server.status_error).to be_nil
    expect(server.dokku_version).to eq("0.38.1")
    expect(server.host_key).to eq("ssh-ed25519 AAAAPINNED")
  end

  it "marks an unreachable server as error with the reason" do
    server.update!(status: :connected)
    allow(Net::SSH).to receive(:start).and_raise(Errno::ECONNREFUSED)

    described_class.perform_now

    server.reload
    expect(server.status).to eq("error")
    expect(server.status_error).to include("ECONNREFUSED")
    expect(Net::SSH).to have_received(:start).twice
  end

  it "does not retry an authentication failure" do
    allow(Net::SSH).to receive(:start).and_raise(Net::SSH::AuthenticationFailed, "dokku")

    described_class.perform_now

    expect(Net::SSH).to have_received(:start).once
    expect(server.reload.status_error).to include("AuthenticationFailed")
  end

  it "holds no transaction open while SSH runs" do
    baseline = ActiveRecord::Base.connection.open_transactions # the spec's own wrapper
    allow(Net::SSH).to receive(:start) do
      expect(ActiveRecord::Base.connection.open_transactions).to eq(baseline)
      raise Errno::EHOSTUNREACH
    end

    described_class.perform_now
  end

  it "keeps going when one server fails unexpectedly" do
    other = create(:server, status: :error)
    allow(Net::SSH).to receive(:start).and_return("dokku version 0.38.1")
    allow(Server).to receive(:find_by).and_call_original
    allow(Server).to receive(:find_by).with(id: server.id).and_raise("boom")

    described_class.perform_now

    expect(other.reload.status).to eq("connected")
  end
end
