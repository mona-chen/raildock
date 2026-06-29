require "rails_helper"

RSpec.describe SshConnectionBuilder do
  let(:organization) { create(:organization) }
  let(:server) { create(:server, organization: organization, host: "192.168.1.1") }

  describe "#options" do
    it "disables strict host-key verification when no host key is stored" do
      builder = described_class.new(server, user: "root")
      expect(builder.options[:verify_host_key]).to eq(:accept_new_or_local_tunnel)
    end

    it "enables strict host-key verification when a host key is stored" do
      server.update!(host_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHZXwtgEdpUYsSkf7K9p7+CdMGU7wyFjuMoUohqLKaZW test")
      builder = described_class.new(server, user: "root")
      expect(builder.options[:verify_host_key]).to eq(:secure)
      expect(builder.options[:user_known_hosts_file]).to be_present
    end

    it "sets a host_key_alias for root user" do
      builder = described_class.new(server, user: "root")
      expect(builder.options[:host_key_alias]).to eq("#{server.host}-root")
    end

    it "does not set a host_key_alias for non-root user" do
      builder = described_class.new(server, user: "dokku")
      expect(builder.options[:host_key_alias]).to be_nil
    end
  end

  describe "#capture_host_key!" do
    it "stores the host key and fingerprint from the session" do
      builder = described_class.new(server, user: "root")
      fake_key = double("key", ssh_type: "ssh-ed25519", to_blob: "fake-blob")
      session = double("session", host_keys: [ fake_key ])

      builder.capture_host_key!(session)

      expect(server.reload.host_key).to start_with("ssh-ed25519 ")
      expect(server.host_key_fingerprint).to start_with("SHA256:")
    end

    it "is a no-op when a host key is already stored" do
      server.update!(host_key: "ssh-ed25519 existing")
      builder = described_class.new(server, user: "root")
      session = double("session", host_keys: [ double("key") ])

      builder.capture_host_key!(session)
      expect(server.reload.host_key).to eq("ssh-ed25519 existing")
    end
  end
end
