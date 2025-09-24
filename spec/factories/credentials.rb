FactoryBot.define do
  factory :credential do
    association :node
    username { "dbuser" }
    password { "secure_password" }
    
    trait :admin do
      username { "admin" }
    end
    
    trait :readonly do
      username { "readonly" }
    end
  end
end
