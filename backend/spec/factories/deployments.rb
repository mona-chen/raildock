FactoryBot.define do
  factory :deployment do
    status { :succeeded }
    commit_sha { Faker::Alphanumeric.alphanumeric(number: 7) }
    started_at { 1.hour.ago }
    completed_at { 30.minutes.ago }
    association :service
  end
end
