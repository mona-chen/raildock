require "rails_helper"

RSpec.describe ServerBootstrapCommandBuilder do
  let(:organization) { create(:organization) }

  describe "#build" do
    it "generates an SSH key if missing and returns the public key and command" do
      builder = described_class.new(organization, base_url: "https://raildock.example.com")
      result = builder.build

      expect(result[:public_key]).to start_with("ssh-ed25519 ")
      expect(result[:command]).to include("https://raildock.example.com/bootstrap.sh")
      expect(result[:command]).to include(result[:public_key].split.first) # key type
      expect(organization.reload.ssh_key).to be_present
    end

    it "reuses an existing SSH key" do
      existing = create(:organization_ssh_key, organization: organization)
      builder = described_class.new(organization, base_url: "https://raildock.example.com")
      result = builder.build

      expect(result[:public_key]).to eq(existing.public_key)
    end
  end
end
