FactoryBot.define do
  factory :process_type do
    name { "web" }
    quantity { 1 }
    running { 1 }
    command { "bundle exec puma -C config/puma.rb" }
    association :service
  end
end
