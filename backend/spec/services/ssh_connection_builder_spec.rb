require "rails_helper"

RSpec.describe SshConnectionBuilder do
  let(:organization) { create(:organization) }
  let(:server) { create(:server, organization: organization, host: "192.168.1.1") }

  describe "#options" do
    it "uses the host-key verifier when no host key is stored" do
      builder = SshConnectionBuilder.new(server, user: "root")
      expect(builder.options[:verify_host_key]).to be_a(SshConnectionBuilder::HostKeyVerifier)
    end

    it "uses the host-key verifier when a host key is stored" do
      server.update!(host_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHZXwtgEdpUYsSkf7K9p7+CdMGU7wyFjuMoUohqLKaZW test")
      builder = SshConnectionBuilder.new(server, user: "root")
      expect(builder.options[:verify_host_key]).to be_a(SshConnectionBuilder::HostKeyVerifier)
    end

    it "sets a host_key_alias for root user" do
      builder = SshConnectionBuilder.new(server, user: "root")
      expect(builder.options[:host_key_alias]).to eq("#{server.host}-root")
    end

    it "does not set a host_key_alias for non-root user" do
      builder = described_class.new(server, user: "dokku")
      expect(builder.options[:host_key_alias]).to be_nil
    end
  end

  describe "#capture_host_key!" do
    it "stores the host key and fingerprint from the session" do
      builder = SshConnectionBuilder.new(server, user: "root")
      fake_key = double("key", ssh_type: "ssh-ed25519", to_blob: "fake-blob")
      transport = double("transport", host_keys: [ fake_key ])
      session = double("session", transport: transport)

      builder.capture_host_key!(session)

      expect(server.host_key).to start_with("ssh-ed25519 ")
      expect(server.host_key_fingerprint).to start_with("SHA256:")
    end

    it "captures multiple host keys when available" do
      builder = SshConnectionBuilder.new(server, user: "root")
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
      builder = SshConnectionBuilder.new(server, user: "root")
      transport = double("transport", host_keys: [ double("key") ])
      session = double("session", transport: transport)

      builder.capture_host_key!(session)
      expect(server.host_key).to eq("ssh-ed25519 existing")
    end
  end

  describe SshConnectionBuilder::HostKeyVerifier do
    let(:rsa_key) { OpenSSL::PKey::RSA.new(2048) }
    let(:fingerprint) { "SHA256:" + Base64.strict_encode64(Digest::SHA256.digest(rsa_key.public_key.to_blob)) }
    let(:net_ssh_key) { double("key", ssh_type: "ssh-rsa", to_blob: rsa_key.public_key.to_blob) }

    it "accepts and captures a new key when none is stored" do
      builder = SshConnectionBuilder.new(server, user: "root")
      verifier = builder.options[:verify_host_key]

      expect { verifier.verify(key: net_ssh_key, fingerprint: fingerprint) }.not_to raise_error
      expect(server.host_key).to start_with("ssh-rsa ")
      expect(server.host_key_fingerprint).to eq(fingerprint)
    end

    it "accepts a matching stored key" do
      server.update!(host_key: "ssh-rsa #{[ rsa_key.public_key.to_blob ].pack("m0")}")
      verifier = SshConnectionBuilder.new(server, user: "root").options[:verify_host_key]

      expect { verifier.verify(key: net_ssh_key, fingerprint: fingerprint) }.not_to raise_error
    end

    it "rejects a non-matching key" do
      server.update!(host_key: "ssh-rsa #{[ rsa_key.public_key.to_blob ].pack("m0")}")
      verifier = SshConnectionBuilder.new(server, user: "root").options[:verify_host_key]

      expect { verifier.verify(key: net_ssh_key, fingerprint: "SHA256:bbbb") }.to raise_error(Net::SSH::HostKeyMismatch)
    end
  end
end
