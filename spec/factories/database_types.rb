FactoryBot.define do
  factory :database_type do
    sequence(:name) { |n| "PostgreSQL #{n}" }
    sequence(:slug) { |n| "postgresql_#{n}" }
    
    trait :mysql do
      sequence(:name) { |n| "MySQL #{n}" }
      sequence(:slug) { |n| "mysql_#{n}" }
    end
    
    trait :with_versions do
      after(:create) do |database_type|
        create(:database_type_version, database_type: database_type, is_default: true)
        create(:database_type_version, database_type: database_type, version: "16", is_default: false)
      end
    end
  end
end
