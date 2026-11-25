require "rails_helper"

RSpec.describe ServerPackageManager do
  let(:server) { create(:server) }
  let(:id) { "a" * 32 }

  it "reserves one host operation and refuses overlapping requests" do
    expect(ServerPackageUpdateJob).to receive(:perform_later).with(server.id, "start", /\A[a-f0-9]{32}\z/)
    described_class.start(server, "check")
    expect { described_class.start(server.reload, "check") }.to raise_error(ServerPackageManager::Busy)
  end

  it "requires a recent reviewed plan with available updates" do
    expect { described_class.start(server, "install", reviewed_id: id) }.to raise_error(ServerPackageManager::InvalidPlan)
    server.update!(package_updates: { "operation" => { "id" => id, "status" => "completed" }, "checked_at" => 2.hours.ago.iso8601, "status" => "completed", "count" => 2 })
    expect { described_class.start(server, "install", reviewed_id: id) }.to raise_error(ServerPackageManager::InvalidPlan)
  end

  it "schedules the reviewed install independently on systemd, without a shell package list" do
    server.update!(package_updates: { "operation" => { "id" => id, "status" => "scheduled", "kind" => "install", "reviewed_id" => "b" * 32 } })
    host = instance_double(HostEngine)
    allow(HostEngine).to receive(:new).and_return(host)
    expect(host).to receive(:run).with(a_string_including("systemd-run", "--property=Nice=10", "install #{'b' * 32}")).and_return(success: true, output: "raildock_maintenance_started\n")
    allow(ServerPackageUpdateJob).to receive_message_chain(:set, :perform_later)
    described_class.schedule(server, id)
    expect(server.reload.package_updates.dig("operation", "status")).to eq("running")
  end

  it "persists a terminal host result and precise OS without re-enqueueing" do
    server.update!(package_updates: { "error" => "old failure", "operation" => { "id" => id, "status" => "running", "started_at" => Time.current.iso8601 } })
    allow_any_instance_of(HostEngine).to receive(:run).and_return(success: true, output: { id: id, status: "completed", checked_at: Time.current.iso8601, count: 4, os: "Debian GNU/Linux 13", log_tail: "done" }.to_json)
    expect(ServerPackageUpdateJob).not_to receive(:set)
    described_class.poll(server, id)
    expect(server.reload.package_updates).to include("count" => 4)
    expect(server.package_updates).not_to have_key("error")
    expect(server.os).to eq("Debian GNU/Linux 13")
  end

  it "keeps an unreachable operation blocked while reconciling slowly" do
    server.update!(package_updates: { "operation" => { "id" => id, "status" => "running", "started_at" => 5.hours.ago.iso8601 } })
    allow_any_instance_of(HostEngine).to receive(:run).and_return(success: false)
    expect(ServerPackageUpdateJob).to receive_message_chain(:set, :perform_later).with(server.id, "poll", id)
    described_class.poll(server, id)
    expect(server.reload.package_updates.dig("operation", "status")).to eq("running")
    expect(server.package_updates["error"]).to include("systemctl status raildock-packages-#{id}")
  end
end
