FactoryBot.define do
  factory :service_link do
    association :from_service, factory: :service
    association :to_service, factory: :service
  end
end
