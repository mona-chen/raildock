FactoryBot.define do
  factory :git_source do
    provider { "github" }
    connected { true }
    username { Faker::Internet.username }
    access_token { Faker::Alphanumeric.alphanumeric(number: 40) }
    metadata { {} }
    association :user, strategy: :create
  end
end
