FactoryBot.define do
  factory :activity_event do
    action { :deployed }
    message { "Deployed test service" }
    association :project
    service_name { "test-service" }
  end
end
