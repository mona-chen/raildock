FactoryBot.define do
  factory :environment_variable do
    sequence(:key) { |n| "VAR_#{n}_#{SecureRandom.hex(3).upcase}" }
    value { Faker::Lorem.word }
    source { nil }
    is_dokku_internal { false }
    association :service
  end
end
