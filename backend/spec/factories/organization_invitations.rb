FactoryBot.define do
  factory :organization_invitation do
    association :organization
    association :invited_by, factory: :user
    email { Faker::Internet.email }
    role { "member" }
    token { SecureRandom.urlsafe_base64(32) }
    expires_at { 7.days.from_now }
  end
end