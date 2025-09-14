FactoryBot.define do
  factory :node do
    name { "Test Node" }
    terraform_state { nil }
    association :cluster
    association :provider
  end
end
