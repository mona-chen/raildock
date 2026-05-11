FactoryBot.define do
  factory :organization do
    name { Faker::Company.name }
    slug { Faker::Internet.slug(words: name, glue: '-') }
    association :owner, factory: :user
  end
end
