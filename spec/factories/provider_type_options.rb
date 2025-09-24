FactoryBot.define do
  factory :provider_type_option do
    association :provider_type
    key { "api_url" }
    label { "API URL" }
    required { true }
    sensitive { true }

    trait :username do
      key { "username" }
      label { "Username" }
    end

    trait :password do
      key { "password" }
      label { "Password" }
    end

    trait :not_required do
      required { false }
    end

    trait :not_sensitive do
      sensitive { false }
    end
  end
end
