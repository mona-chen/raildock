require "rails_helper"

RSpec.describe SshConnectionBuilder do
  let(:organization) { create(:organization) }
  let(:server) { create(:server, organization: organization, host: "192.168.1.1") }

  describe "#options" do
    it "accepts new host keys when no host key is stored" do
      builder = described_class.new(server, user: "root")
      expect(builder.options[:verify_host_key]).to eq(:accept_new)
    end

    it "verifies against stored host key fingerprint when a key is stored" do
      server.update!(host_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHZXwtgEdpUYsSkf7K9p7+CdMGU7wyFjuMoUohqLKaZW test")
      builder = described_class.new(server, user: "root")
      expect(builder.options[:verify_host_key]).to be_a(SshConnectionBuilder::StoredHostKeyVerifier)
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
      transport = double("transport", host_keys: [ fake_key ])
      session = double("session", transport: transport)

      builder.capture_host_key!(session)

      expect(server.host_key).to start_with("ssh-ed25519 ")
      expect(server.host_key_fingerprint).to start_with("SHA256:")
    end

    it "captures multiple host keys when available" do
      builder = described_class.new(server, user: "root")
      key1 = double("key1", ssh_type: "ssh-ed25519", to_blob: "blob-1")
      key2 = double("key2", ssh_type: "ssh-rsa", to_blob: "blob-2")
      transport = double("transport", host_keys: [ key1, key2 ])
      session = double("session", transport: transport)

      builder.capture_host_key!(session)

      expect(server.host_key.lines.count).to eq(2)
      expect(server.host_key).to include("ssh-ed25519")
      expect(server.host_key).to include("ssh-rsa")
    end

    it "is a no-op when a host key is already stored" do
      server.update!(host_key: "ssh-ed25519 existing")
      builder = described_class.new(server, user: "root")
      transport = double("transport", host_keys: [ double("key") ])
      session = double("session", transport: transport)

      builder.capture_host_key!(session)
      expect(server.reload.host_key).to eq("ssh-ed25519 existing")
    end
  end

  describe SshConnectionBuilder::StoredHostKeyVerifier do
    let(:blob) { [ OpenSSL::PKey::RSA.new(2048).public_key.to_blob ].pack("m0") }
    let(:fingerprint) { "SHA256:" + Base64.strict_encode64(Digest::SHA256.digest(OpenSSL::PKey::RSA.new(2048).public_key.to_blob)) }

    it "accepts a matching stored key" do
      key = OpenSSL::PKey::RSA.new(2048)
      server.update!(host_key: "ssh-rsa #{[ key.public_key.to_blob ].pack("m0")}")
      fp = "SHA256:" + Base64.strict_encode64(Digest::SHA256.digest(key.public_key.to_blob))
      verifier = described_class.new(server)

      expect { verifier.verify(fingerprint: fp) }.not_to raise_error
    end

    it "rejects a non-matching key" do
      server.update!(host_key: "ssh-rsa #{blob}")
      verifier = described_class.new(server)

      expect { verifier.verify(fingerprint: "SHA256:bbbb") }.to raise_error(Net::SSH::HostKeyMismatch)
    end
  end
end
