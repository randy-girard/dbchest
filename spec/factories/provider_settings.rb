FactoryBot.define do
  factory :provider_setting do
    association :provider
    association :provider_type_option
    key { "api_url" }
    value { "https://proxmox.example.com:8006/api2/json" }
    
    trait :username do
      association :provider_type_option, :username
      key { "username" }
      value { "root@pam" }
    end
    
    trait :password do
      association :provider_type_option, :password
      key { "password" }
      value { "secret_password" }
    end
  end
end
