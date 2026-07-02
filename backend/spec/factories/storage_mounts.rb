FactoryBot.define do
  factory :storage_mount do
    host_path { "/var/lib/dokku/data/storage/#{Faker::Internet.domain_word}" }
    container_path { "/app/data" }
    kind { "bind" }
    association :service

    trait :volume do
      host_path { "#{Faker::Internet.domain_word}-data" }
      kind { "volume" }
    end
  end
end
