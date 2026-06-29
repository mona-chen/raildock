FactoryBot.define do
  factory :organization_ssh_key do
    association :organization
    public_key { "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHZXwtgEdpUYsSkf7K9p7+CdMGU7wyFjuMoUohqLKaZW #{organization.slug}" }
    fingerprint { "SHA256:abcdef" }
    private_key { "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----" }
  end
end
