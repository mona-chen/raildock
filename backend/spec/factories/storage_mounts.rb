FactoryBot.define do
  factory :storage_mount do
    host_path { "/var/lib/dokku/data/storage/#{Faker::Internet.domain_word}" }
    container_path { "/app/data" }
    association :service
  end
end
