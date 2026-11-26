FactoryBot.define do
  factory :domain do
    sequence(:hostname) { |n| "app-#{n}.example.com" }
    port { 443 }
    ssl { false }
    letsencrypt { false }
    association :service
  end
end
