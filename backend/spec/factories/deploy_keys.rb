FactoryBot.define do
  factory :deploy_key do
    name { Faker::Internet.domain_word }
    public_key { "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI#{Faker::Alphanumeric.alphanumeric(number: 43)} raildock-deploy" }
    private_key { "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----" }
    fingerprint { "SHA256:#{Faker::Alphanumeric.alphanumeric(number: 43)}" }
    association :user
  end
end
