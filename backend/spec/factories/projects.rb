FactoryBot.define do
  factory :project do
    name { Faker::App.name }
    description { Faker::Lorem.sentence }
    environment { :production }
    association :server
    shared_vars { [] }
  end
end
