FactoryBot.define do
  factory :plugin do
    sequence(:slug) { |n| "test-plugin-#{n}" }
    name { "Test Plugin" }
    description { "A plugin for testing" }
    category { "tool" }
    status { "enabled" }
    icon { "box" }
    config_schema { {} }
  end
end
