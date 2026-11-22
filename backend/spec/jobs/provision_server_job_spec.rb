require "rails_helper"

RSpec.describe ProvisionServerJob do
  it "runs on the maintenance queue, away from deployments and backups" do
    expect(described_class.queue_name).to eq("maintenance")
  end

  describe ".bootstrap_command" do
    let(:public_key) { "ssh-ed25519 AAAAC3Nza raildock@org" }

    it "shell-escapes the external proxy network" do
      command = described_class.bootstrap_command(
        "https://raildock.example.com/", public_key, "external",
        external_proxy_network: "proxy'; touch /tmp/pwned; echo '"
      )

      expect(command).to include("EXTERNAL_PROXY_NETWORK=#{Shellwords.escape("proxy'; touch /tmp/pwned; echo '")}")
      expect(command).not_to include("EXTERNAL_PROXY_NETWORK='proxy'")
      expect(command).to include("PROXY_MODE=external")
      expect(command).to include("https://raildock.example.com/bootstrap.sh")
      expect(command).to end_with("bash -s -- #{Shellwords.escape(public_key)}")
    end

    it "refuses an unknown proxy mode" do
      expect {
        described_class.bootstrap_command("https://x", public_key, "managed; reboot")
      }.to raise_error(ArgumentError)
    end

    it "elevates with non-interactive sudo when the admin user is not root" do
      command = described_class.bootstrap_command("https://x", public_key, "managed")
      expect(command).to include(%q(if [ "$(id -u)" -eq 0 ]; then RD_SUDO=''; else RD_SUDO='sudo -n'; fi;))
      expect(command).to include("| $RD_SUDO env PROXY_MODE=managed bash -s --")
    end
  end

  describe "#perform" do
    let(:organization) { create(:organization) }
    let(:setup_id) { SecureRandom.uuid }

    before do
      OrganizationSshKeyService.generate(organization)
      allow(ActionCable.server).to receive(:broadcast)
    end

    it "fails before connecting when the host is already a server in the organization" do
      create(:server, organization: organization, host: "10.0.0.5", name: "Existing")
      expect(Net::SSH).not_to receive(:start)

      described_class.perform_now(setup_id, organization.id, "10.0.0.5", "root", "https://raildock.example.com")

      expect(ActionCable.server).to have_received(:broadcast).with(
        "server_setup:#{setup_id}", hash_including(type: "failed", error: a_string_including("already connected"))
      )
    end

    it "fails before connecting on an unknown proxy mode" do
      expect(Net::SSH).not_to receive(:start)

      described_class.perform_now(setup_id, organization.id, "10.0.0.6", "root", "https://x", proxy_mode: "bogus")

      expect(ActionCable.server).to have_received(:broadcast).with(
        "server_setup:#{setup_id}", hash_including(type: "failed")
      )
    end
  end
end
