class UpdatePostgreSqlInstallationCommands < ActiveRecord::Migration[8.0]
  def up
    # Update PostgreSQL installation commands to handle Ubuntu version compatibility
    postgresql_type = DatabaseType.find_by(slug: 'postgresql')
    return unless postgresql_type

    # Update PostgreSQL 12 - available in Ubuntu 20.04 default repos
    pg12 = postgresql_type.database_type_versions.find_by(version: '12')
    pg12&.update!(
      install_command: 'DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-12 postgresql-contrib-12'
    )

    # Update PostgreSQL 13 - available in Ubuntu 20.04 default repos
    pg13 = postgresql_type.database_type_versions.find_by(version: '13')
    pg13&.update!(
      install_command: 'DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-13 postgresql-contrib-13'
    )

    # Update PostgreSQL 14 - needs PostgreSQL APT repository
    pg14 = postgresql_type.database_type_versions.find_by(version: '14')
    pg14&.update!(
      install_command: <<~CMD.strip
        # Add PostgreSQL APT repository
        wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
        echo "deb http://apt-archive.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-14 postgresql-contrib-14
      CMD
    )

    # Update PostgreSQL 15 - needs PostgreSQL APT repository
    pg15 = postgresql_type.database_type_versions.find_by(version: '15')
    pg15&.update!(
      install_command: <<~CMD.strip
        # Add PostgreSQL APT repository
        wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
        echo "deb http://apt-archive.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-15 postgresql-contrib-15
      CMD
    )

    # Update PostgreSQL 16 - needs newer Ubuntu version, error on unsupported systems
    pg16 = postgresql_type.database_type_versions.find_by(version: '16')
    pg16&.update!(
      install_command: <<~CMD.strip
        # Check Ubuntu version and ensure PostgreSQL 16 is supported
        UBUNTU_CODENAME=$(lsb_release -cs)
        if [[ "$UBUNTU_CODENAME" == "focal" ]]; then
          # PostgreSQL 16 is not available on Ubuntu 20.04
          echo "ERROR: PostgreSQL 16 is not supported on Ubuntu 20.04 (focal)"
          echo "Available PostgreSQL versions for Ubuntu 20.04: 12, 13, 14, 15"
          echo "Please select a different PostgreSQL version or upgrade your Ubuntu version"
          exit 1
        else
          # For newer Ubuntu versions (22.04+)
          wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
          echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
          apt-get update
          DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-16 postgresql-contrib-16
        fi
      CMD
    )
  end

  def down
    # Revert to simpler installation commands
    postgresql_type = DatabaseType.find_by(slug: 'postgresql')
    return unless postgresql_type

    postgresql_type.database_type_versions.update_all(
      install_command: 'DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-contrib'
    )
  end
end
