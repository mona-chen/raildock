require "rails_helper"

RSpec.describe OrganizationSshKey, type: :model do
  let(:organization) { create(:organization) }

  describe "validations" do
    it "is valid with valid attributes" do
      key = OrganizationSshKey.new(
        organization: organization,
        public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHZXwtgEdpUYsSkf7K9p7+CdMGU7wyFjuMoUohqLKaZW test",
        fingerprint: "SHA256:abcdef",
        private_key: "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
      )
      expect(key).to be_valid
    end

    it "requires an organization" do
      key = OrganizationSshKey.new(public_key: "x", fingerprint: "y", private_key: "z")
      expect(key).not_to be_valid
    end

    it "requires a unique organization" do
      create(:organization_ssh_key, organization: organization)
      key = build(:organization_ssh_key, organization: organization)
      expect(key).not_to be_valid
    end
  end

  describe "#private_key" do
    it "encrypts and decrypts the private key" do
      original = "-----BEGIN OPENSSH PRIVATE KEY-----\ntest-value\n-----END OPENSSH PRIVATE KEY-----"
      key = create(:organization_ssh_key, organization: organization, private_key: original)

      expect(key.private_key).to eq(original)
      expect(key[:private_key_ciphertext]).to be_present
      expect(key[:private_key_ciphertext]).not_to eq(original)
    end

    it "returns nil when ciphertext is blank" do
      key = OrganizationSshKey.new
      expect(key.private_key).to be_nil
    end
  end
end
