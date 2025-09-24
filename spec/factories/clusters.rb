FactoryBot.define do
  factory :cluster do
    sequence(:name) { |n| "Test Cluster #{n}" }
    association :database_type
  end
end
