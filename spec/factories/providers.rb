FactoryBot.define do
  factory :provider do
    name { "Test Provider" }
    association :provider_type
  end
end
