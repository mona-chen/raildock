FactoryBot.define do
  factory :domain do
    hostname { Faker::Internet.domain_name }
    port { 443 }
    ssl { false }
    letsencrypt { false }
    association :service
  end
end
