FactoryBot.define do
  factory :organization_membership do
    association :user
    association :organization
    role { :member }
  end
end
