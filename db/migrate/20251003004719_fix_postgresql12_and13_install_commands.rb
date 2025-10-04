class FixPostgresql12And13InstallCommands < ActiveRecord::Migration[8.0]
  def up
    # PostgreSQL 12 and 13 are NOT in Ubuntu default repositories
    # They need the PostgreSQL APT repository to be added first
    postgresql_type = DatabaseType.find_by(slug: 'postgresql')
    return unless postgresql_type

    # Update PostgreSQL 12 - needs PostgreSQL APT repository
    pg12 = postgresql_type.database_type_versions.find_by(version: '12')
    pg12&.update!(
      install_command: <<~CMD.strip
        # Add PostgreSQL APT repository
        wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
        echo "deb http://apt-archive.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-12 postgresql-contrib-12
      CMD
    )

    # Update PostgreSQL 13 - needs PostgreSQL APT repository
    pg13 = postgresql_type.database_type_versions.find_by(version: '13')
    pg13&.update!(
      install_command: <<~CMD.strip
        # Add PostgreSQL APT repository
        wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
        echo "deb http://apt-archive.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-13 postgresql-contrib-13
      CMD
    )
  end

  def down
    # Revert to simple commands (which won't work, but this is just for rollback)
    postgresql_type = DatabaseType.find_by(slug: 'postgresql')
    return unless postgresql_type

    pg12 = postgresql_type.database_type_versions.find_by(version: '12')
    pg12&.update!(
      install_command: 'DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-12 postgresql-contrib-12'
    )

    pg13 = postgresql_type.database_type_versions.find_by(version: '13')
    pg13&.update!(
      install_command: 'DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-13 postgresql-contrib-13'
    )
  end
end
