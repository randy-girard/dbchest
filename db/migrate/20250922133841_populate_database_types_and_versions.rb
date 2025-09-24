class PopulateDatabaseTypesAndVersions < ActiveRecord::Migration[8.0]
  def up
    # Create PostgreSQL database type
    postgresql_type = DatabaseType.create!(
      name: 'PostgreSQL',
      slug: 'postgresql'
    )

    # Create PostgreSQL versions with installation commands
    postgresql_versions = [
      {
        version: '12',
        install_command: 'DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-12 postgresql-contrib-12',
        default_port: 5432,
        service_name: 'postgresql',
        data_directory_pattern: '/var/lib/postgresql/12/main',
        config_file_pattern: '/etc/postgresql/12/main/postgresql.conf',
        is_default: false
      },
      {
        version: '13',
        install_command: 'DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-13 postgresql-contrib-13',
        default_port: 5432,
        service_name: 'postgresql',
        data_directory_pattern: '/var/lib/postgresql/13/main',
        config_file_pattern: '/etc/postgresql/13/main/postgresql.conf',
        is_default: false
      },
      {
        version: '14',
        install_command: 'DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-14 postgresql-contrib-14',
        default_port: 5432,
        service_name: 'postgresql',
        data_directory_pattern: '/var/lib/postgresql/14/main',
        config_file_pattern: '/etc/postgresql/14/main/postgresql.conf',
        is_default: false
      },
      {
        version: '15',
        install_command: 'DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-15 postgresql-contrib-15',
        default_port: 5432,
        service_name: 'postgresql',
        data_directory_pattern: '/var/lib/postgresql/15/main',
        config_file_pattern: '/etc/postgresql/15/main/postgresql.conf',
        is_default: true # Current default
      },
      {
        version: '16',
        install_command: 'DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-16 postgresql-contrib-16',
        default_port: 5432,
        service_name: 'postgresql',
        data_directory_pattern: '/var/lib/postgresql/16/main',
        config_file_pattern: '/etc/postgresql/16/main/postgresql.conf',
        is_default: false
      }
    ]

    postgresql_versions.each do |version_data|
      postgresql_type.database_type_versions.create!(version_data)
    end

    # Create MySQL database type for future use
    mysql_type = DatabaseType.create!(
      name: 'MySQL',
      slug: 'mysql'
    )

    # Create MySQL versions
    mysql_versions = [
      {
        version: '8.0',
        install_command: 'DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server-8.0',
        default_port: 3306,
        service_name: 'mysql',
        data_directory_pattern: '/var/lib/mysql',
        config_file_pattern: '/etc/mysql/mysql.conf.d/mysqld.cnf',
        is_default: true
      }
    ]

    mysql_versions.each do |version_data|
      mysql_type.database_type_versions.create!(version_data)
    end

    # Get the default PostgreSQL version (15)
    default_pg_version = postgresql_type.database_type_versions.find_by(version: '15')

    # Update existing clusters to use PostgreSQL type
    Cluster.where(database_type_id: nil).update_all(database_type_id: postgresql_type.id)

    # Update existing nodes to use PostgreSQL 15 (current default)
    Node.where(database_type_version_id: nil).update_all(database_type_version_id: default_pg_version.id)
  end

  def down
    # Remove the associations first
    Node.update_all(database_type_version_id: nil)
    Cluster.update_all(database_type_id: nil)

    # Then remove the data
    DatabaseTypeVersion.delete_all
    DatabaseType.delete_all
  end
end
