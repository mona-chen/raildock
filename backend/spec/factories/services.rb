FactoryBot.define do
  factory :service do
    name { Faker::Internet.domain_word }
    service_type { :app }
    subtype { "web" }
    status { :running }
    builder { :nixpacks }
    association :project
    dokku_app_name { "#{project.name.parameterize}-#{name.parameterize}" }
    config { {} }
    restart_policy { :on_failure }
    restart_max_retries { 10 }
    locked { false }

    trait :database do
      service_type { :database }
      subtype { "postgres" }
      builder { nil }
      version { "16" }
    end

    trait :with_env_vars do
      after(:create) do |service|
        create_list(:environment_variable, 3, service: service)
      end
    end

    trait :with_domains do
      after(:create) do |service|
        create_list(:domain, 2, service: service)
      end
    end
  end
end
