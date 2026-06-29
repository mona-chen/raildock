require "rails_helper"

RSpec.describe OrganizationSshKeyService do
  let(:organization) { create(:organization) }

  describe ".generate" do
    it "creates a valid Ed25519 key pair for the organization" do
      key = described_class.generate(organization)

      expect(key).to be_persisted
      expect(key.organization).to eq(organization)
      expect(key.public_key).to start_with("ssh-ed25519 ")
      expect(key.private_key).to include("BEGIN OPENSSH PRIVATE KEY")
      expect(key.fingerprint).to start_with("SHA256:")
    end

    it "is idempotent" do
      first = described_class.generate(organization)
      second = described_class.generate(organization)

      expect(second.id).to eq(first.id)
      expect(OrganizationSshKey.count).to eq(1)
    end
  end

  describe ".ensure_key!" do
    it "returns existing key if present" do
      existing = create(:organization_ssh_key, organization: organization)
      expect(described_class.ensure_key!(organization).id).to eq(existing.id)
    end

    it "generates a key when missing" do
      expect { described_class.ensure_key!(organization) }
        .to change(OrganizationSshKey, :count).by(1)
    end
  end
end
