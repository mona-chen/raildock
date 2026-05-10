FactoryBot.define do
  factory :environment_variable do
    key { Faker::Internet.domain_word.upcase }
    value { Faker::Lorem.word }
    source { nil }
    is_dokku_internal { false }
    association :service
  end
end
