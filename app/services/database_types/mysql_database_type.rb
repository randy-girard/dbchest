require_relative "../cloud_init_generators/mysql_cloud_init_generator"

module DatabaseTypes
  class MysqlDatabaseType < BaseDatabaseType
    def supports_logical_replication?
      major_version >= 8
    end

    def supports_streaming_replication?
      major_version >= 5
    end

    def generate_cloud_init_script(node, is_replica: false)
      CloudInitGenerators::MysqlCloudInitGenerator.new(self, node).generate(is_replica: is_replica)
    end

    def primary_configuration_commands
      [
        "echo \"server-id = 1\" >> #{config_file_path}",
        "echo \"log-bin = mysql-bin\" >> #{config_file_path}",
        "echo \"binlog-format = ROW\" >> #{config_file_path}",
        "echo \"gtid-mode = ON\" >> #{config_file_path}",
        "echo \"enforce-gtid-consistency = ON\" >> #{config_file_path}",
        "echo \"bind-address = 0.0.0.0\" >> #{config_file_path}"
      ]
    end

    def replica_configuration_commands
      [
        "echo \"server-id = 2\" >> #{config_file_path}",
        "echo \"read-only = ON\" >> #{config_file_path}",
        "echo \"super-read-only = ON\" >> #{config_file_path}",
        "echo \"relay-log = mysql-relay-bin\" >> #{config_file_path}"
      ]
    end

    def readiness_check_command
      "mysqladmin ping"
    end

    def create_sample_data_commands
      [
        "mysql -e \"CREATE DATABASE IF NOT EXISTS dbchest_sample;\"",
        "mysql -D dbchest_sample -e \"",
        "  CREATE TABLE IF NOT EXISTS sample_data (",
        "    id INT AUTO_INCREMENT PRIMARY KEY,",
        "    name VARCHAR(100),",
        "    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP",
        "  );",
        "  INSERT INTO sample_data (name) VALUES ('Initial Data'), ('Sample Record');",
        "\""
      ]
    end

    def recovery_check_command
      "mysql -e \"SELECT @@read_only;\" | grep -q \"1\""
    end

    def replication_lag_check_commands
      [
        "mysql -e \"SHOW SLAVE STATUS\\G\" | grep \"Seconds_Behind_Master\" || echo \"Could not check replication lag\""
      ]
    end

    private

    def config_file_path
      "/etc/mysql/mysql.conf.d/mysqld.cnf"
    end

    def data_directory_path
      "/var/lib/mysql"
    end
  end
end
