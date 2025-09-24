FactoryBot.define do
  factory :node do
    sequence(:name) { |n| "Test Node #{n}" }
    terraform_state { {} }
    association :cluster
    association :provider
    association :database_type_version

    trait :primary do
      parent_node { nil }
    end

    trait :replica do
      association :parent_node, factory: :node
    end

    trait :active do
      status { 'active' }
    end

    trait :pending do
      status { 'pending' }
    end
  end
end
