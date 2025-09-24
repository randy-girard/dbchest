FactoryBot.define do
  factory :database_type_version do
    association :database_type
    sequence(:version) { |n| "15.#{n}" }
    install_command { "DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-15 postgresql-contrib-15" }
    default_port { 5432 }
    service_name { "postgresql" }
    data_directory_pattern { "/var/lib/postgresql/15/main" }
    config_file_pattern { "/etc/postgresql/15/main/postgresql.conf" }
    is_default { false }

    trait :default do
      is_default { true }
    end

    trait :postgresql_12 do
      version { "12" }
      install_command { "DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-12 postgresql-contrib-12" }
      data_directory_pattern { "/var/lib/postgresql/12/main" }
      config_file_pattern { "/etc/postgresql/12/main/postgresql.conf" }
    end

    trait :postgresql_16 do
      version { "16" }
      install_command { "DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-16 postgresql-contrib-16" }
      data_directory_pattern { "/var/lib/postgresql/16/main" }
      config_file_pattern { "/etc/postgresql/16/main/postgresql.conf" }
    end

    trait :mysql_8 do
      association :database_type, :mysql
      version { "8.0" }
      install_command { "DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server-8.0" }
      default_port { 3306 }
      service_name { "mysql" }
      data_directory_pattern { "/var/lib/mysql" }
      config_file_pattern { "/etc/mysql/mysql.conf.d/mysqld.cnf" }
    end
  end
end
