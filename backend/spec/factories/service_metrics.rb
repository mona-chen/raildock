FactoryBot.define do
  factory :service_metric do
    service
    cpu { 25.5 }
    memory { 40.0 }
    memory_used { 536870912 }
    memory_limit { 1073741824 }
    network_in { 0 }
    network_out { 0 }
    sampled_at { Time.current }
  end
end
