class AddMysqlVersions81Through84 < ActiveRecord::Migration[8.0]
  def up
    # Find MySQL database type
    mysql_type = DatabaseType.find_by(slug: "mysql")
    return unless mysql_type

    # MySQL 8.4 (Innovation Release - Latest)
    mysql_type.database_type_versions.find_or_create_by(
      version: "8.4"
    ) do |version|
      version.install_command = <<~CMD.strip
        # Check Ubuntu version and install accordingly
        if [ "$(lsb_release -rs)" = "20.04" ]; then
          echo "MySQL 8.4 requires Ubuntu 22.04 or later."
          exit 1
        else
          # Install MySQL 8.4 from official repository
          wget https://dev.mysql.com/get/mysql-apt-config_0.8.29-1_all.deb
          DEBIAN_FRONTEND=noninteractive dpkg -i mysql-apt-config_0.8.29-1_all.deb
          apt-get update
          DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server mysql-client
        fi
      CMD
      version.default_port = 3306
      version.service_name = "mysql"
      version.data_directory_pattern = "/var/lib/mysql"
      version.config_file_pattern = "/etc/mysql/mysql.conf.d/mysqld.cnf"
      version.is_default = false
    end

    # MySQL 8.3 (Innovation Release)
    mysql_type.database_type_versions.find_or_create_by(
      version: "8.3"
    ) do |version|
      version.install_command = <<~CMD.strip
        # Check Ubuntu version and install accordingly
        if [ "$(lsb_release -rs)" = "20.04" ]; then
          echo "MySQL 8.3 requires Ubuntu 22.04 or later."
          exit 1
        else
          # Install MySQL 8.3 from official repository
          wget https://dev.mysql.com/get/mysql-apt-config_0.8.28-1_all.deb
          DEBIAN_FRONTEND=noninteractive dpkg -i mysql-apt-config_0.8.28-1_all.deb
          apt-get update
          DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server-8.3 mysql-client-8.3
        fi
      CMD
      version.default_port = 3306
      version.service_name = "mysql"
      version.data_directory_pattern = "/var/lib/mysql"
      version.config_file_pattern = "/etc/mysql/mysql.conf.d/mysqld.cnf"
      version.is_default = false
    end

    # MySQL 8.2 (Innovation Release)
    mysql_type.database_type_versions.find_or_create_by(
      version: "8.2"
    ) do |version|
      version.install_command = <<~CMD.strip
        # Check Ubuntu version and install accordingly
        if [ "$(lsb_release -rs)" = "20.04" ]; then
          echo "MySQL 8.2 requires Ubuntu 22.04 or later."
          exit 1
        else
          # Install MySQL 8.2 from official repository
          wget https://dev.mysql.com/get/mysql-apt-config_0.8.27-1_all.deb
          DEBIAN_FRONTEND=noninteractive dpkg -i mysql-apt-config_0.8.27-1_all.deb
          apt-get update
          DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server-8.2 mysql-client-8.2
        fi
      CMD
      version.default_port = 3306
      version.service_name = "mysql"
      version.data_directory_pattern = "/var/lib/mysql"
      version.config_file_pattern = "/etc/mysql/mysql.conf.d/mysqld.cnf"
      version.is_default = false
    end

    # MySQL 8.1 (Innovation Release)
    mysql_type.database_type_versions.find_or_create_by(
      version: "8.1"
    ) do |version|
      version.install_command = <<~CMD.strip
        # Check Ubuntu version and install accordingly
        if [ "$(lsb_release -rs)" = "20.04" ]; then
          echo "MySQL 8.1 requires Ubuntu 22.04 or later."
          exit 1
        else
          # Install MySQL 8.1 from official repository
          wget https://dev.mysql.com/get/mysql-apt-config_0.8.26-1_all.deb
          DEBIAN_FRONTEND=noninteractive dpkg -i mysql-apt-config_0.8.26-1_all.deb
          apt-get update
          DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server-8.1 mysql-client-8.1
        fi
      CMD
      version.default_port = 3306
      version.service_name = "mysql"
      version.data_directory_pattern = "/var/lib/mysql"
      version.config_file_pattern = "/etc/mysql/mysql.conf.d/mysqld.cnf"
      version.is_default = false
    end
  end

  def down
    # Find MySQL database type
    mysql_type = DatabaseType.find_by(slug: "mysql")
    return unless mysql_type

    # Remove the added versions
    mysql_type.database_type_versions.where(version: [ "8.1", "8.2", "8.3", "8.4" ]).destroy_all
  end
end
