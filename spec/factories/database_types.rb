FactoryBot.define do
  factory :database_type do
    name { "PostgreSQL" }
    slug { "postgresql" }

    # Use initialize_with to find or create by slug to avoid duplicates
    initialize_with { DatabaseType.find_or_create_by(slug: slug) { |dt| dt.name = name } }

    trait :mysql do
      name { "MySQL" }
      slug { "mysql" }
    end

    trait :mongodb do
      name { "MongoDB" }
      slug { "mongodb" }
    end

    trait :cassandra do
      name { "Cassandra" }
      slug { "cassandra" }
    end

    trait :with_versions do
      after(:create) do |database_type|
        # Only create versions if they don't exist
        unless database_type.database_type_versions.exists?
          create(:database_type_version, database_type: database_type, is_default: true)
          create(:database_type_version, database_type: database_type, version: "16", is_default: false)
        end
      end
    end
  end
end
