require "rails_helper"

RSpec.describe HostUpdateRunner do
  let(:server) { create(:server, host: "host.docker.internal") }
  let(:host) { instance_double(HostEngine) }
  before do
    stub_const("ENV", ENV.to_h.merge("HOSTNAME" => "abcdef123456"))
    allow(HostEngine).to receive(:new).with(server).and_return(host)
  end

  it "acknowledges detached scheduling and verifies the target container identity" do
    command = nil
    allow(host).to receive(:run) { |value| command = value; { success: true, output: "raildock_update_scheduled\n" } }
    result = described_class.new(server: server).schedule("0.2.0")
    expect(result).to include(success: true, operation_id: a_string_matching(/\A[a-f0-9]{32}\z/))
    expect(command).to include("systemd-run", "--property=Type=exec", "abcdef123456*", "docker compose")
    expect(SystemSetting.find_by(key: "update_operation_id").value).to eq(result[:operation_id])
  end

  it "refuses shell syntax in an image tag before contacting the host" do
    expect(host).not_to receive(:run)
    expect(described_class.new(server: server).schedule("0.2.0; reboot")).to include(success: false)
  end

  it "does not report a failed host preflight as a scheduled update" do
    allow(host).to receive(:run).and_return(success: false, output: "host mismatch")
    expect(described_class.new(server: server).schedule("0.2.0")).to include(success: false)
    expect(SystemSetting.find_by(key: "update_operation_id")).to be_nil
  end

  it "returns only allowlisted host status fields" do
    allow(host).to receive(:run).and_return(success: true, output: { status: "rolled_back", version: "0.2.0", secret: "hidden" }.to_json)
    expect(described_class.new(server: server).status("a" * 32)).to eq("status" => "rolled_back", "version" => "0.2.0")
  end
end
