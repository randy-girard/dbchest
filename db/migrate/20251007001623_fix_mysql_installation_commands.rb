class FixMysqlInstallationCommands < ActiveRecord::Migration[8.0]
  def up
    # Find MySQL database type
    mysql_type = DatabaseType.find_by(slug: "mysql")
    return unless mysql_type

    # Update MySQL 8.0 with proper installation command
    mysql_80 = mysql_type.database_type_versions.find_by(version: "8.0")
    if mysql_80
      mysql_80.update!(
        install_command: <<~CMD.strip
          # MySQL 8.0 installation for Ubuntu
          DEBIAN_FRONTEND=noninteractive apt-get update
          DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server mysql-client

          # Ensure MySQL is started
          systemctl start mysql
          systemctl enable mysql
        CMD
      )
    end

    # Update MySQL 5.7 with proper installation command
    mysql_57 = mysql_type.database_type_versions.find_by(version: "5.7")
    if mysql_57
      mysql_57.update!(
        install_command: <<~CMD.strip
          # Check Ubuntu version for MySQL 5.7 compatibility
          UBUNTU_VERSION=$(lsb_release -rs)

          if [ "$UBUNTU_VERSION" = "20.04" ]; then
            # MySQL 5.7 is available in Ubuntu 20.04 universe repository
            DEBIAN_FRONTEND=noninteractive apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common
            add-apt-repository universe -y
            DEBIAN_FRONTEND=noninteractive apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server-5.7 mysql-client-5.7
          elif [ "$UBUNTU_VERSION" = "18.04" ]; then
            # MySQL 5.7 is the default in Ubuntu 18.04
            DEBIAN_FRONTEND=noninteractive apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server mysql-client
          else
            # For Ubuntu 22.04+ or other versions, MySQL 5.7 is not available in default repos
            # Need to use MySQL APT repository
            echo "MySQL 5.7 requires Ubuntu 18.04 or 20.04. Current version: $UBUNTU_VERSION"
            echo "For Ubuntu 22.04+, please use MySQL 8.0 or later."
            exit 1
          fi

          # Ensure MySQL is started
          systemctl start mysql
          systemctl enable mysql
        CMD
      )
    end
  end

  def down
    # Find MySQL database type
    mysql_type = DatabaseType.find_by(slug: "mysql")
    return unless mysql_type

    # Revert MySQL 8.0 to original command
    mysql_80 = mysql_type.database_type_versions.find_by(version: "8.0")
    if mysql_80
      mysql_80.update!(
        install_command: "apt-get update && apt-get install -y mysql-server mysql-client"
      )
    end

    # Revert MySQL 5.7 to original command
    mysql_57 = mysql_type.database_type_versions.find_by(version: "5.7")
    if mysql_57
      mysql_57.update!(
        install_command: "apt-get update && apt-get install -y mysql-server-5.7 mysql-client-5.7"
      )
    end
  end
end
