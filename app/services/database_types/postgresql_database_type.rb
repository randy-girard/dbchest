require_relative "../cloud_init_generators/postgresql_cloud_init_generator"

module DatabaseTypes
  class PostgresqlDatabaseType < BaseDatabaseType
    # Register this handler with the base class
    BaseDatabaseType.register("postgresql", self)
    def supports_logical_replication?
      major_version >= 10
    end

    def supports_streaming_replication?
      major_version >= 9
    end

    def generate_cloud_init_script(node, is_replica: false)
      CloudInitGenerators::PostgresqlCloudInitGenerator.new(self, node).generate(is_replica: is_replica)
    end

    def primary_configuration_commands
      [
        "echo \"wal_level = replica\" >> #{config_file_path}",
        "echo \"max_wal_senders = 10\" >> #{config_file_path}",
        "echo \"max_replication_slots = 10\" >> #{config_file_path}",
        "echo \"archive_mode = on\" >> #{config_file_path}",
        "echo \"archive_command = 'test ! -f /var/lib/postgresql/archive/%f && cp %p /var/lib/postgresql/archive/%f'\" >> #{config_file_path}",
        "echo \"listen_addresses = '*'\" >> #{config_file_path}",
        "mkdir -p /var/lib/postgresql/archive",
        "chown postgres:postgres /var/lib/postgresql/archive"
      ]
    end

    def replica_configuration_commands
      [
        "echo \"hot_standby = on\" >> #{config_file_path}",
        "echo \"max_standby_streaming_delay = 30s\" >> #{config_file_path}",
        "echo \"wal_receiver_status_interval = 10s\" >> #{config_file_path}",
        "echo \"listen_addresses = '*'\" >> #{config_file_path}"
      ]
    end

    def readiness_check_command
      "sudo -u postgres pg_isready -q"
    end

    def create_sample_data_commands
      [
        "sudo -u postgres psql -c \"CREATE DATABASE dbchest_sample;\" || echo \"Sample database may already exist\"",
        "sudo -u postgres psql -d dbchest_sample -c \"",
        "  CREATE TABLE IF NOT EXISTS sample_data (",
        "    id SERIAL PRIMARY KEY,",
        "    name VARCHAR(100),",
        "    created_at TIMESTAMP DEFAULT NOW()",
        "  );",
        "  INSERT INTO sample_data (name) VALUES ('Initial Data'), ('Sample Record');",
        "\" || echo \"Sample data setup completed\""
      ]
    end

    def recovery_check_command
      "sudo -u postgres psql -c \"SELECT pg_is_in_recovery();\" | grep -q \"t\""
    end

    def replication_lag_check_commands
      [
        "sudo -u postgres psql -c \"SELECT CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() \\
THEN 0 ELSE EXTRACT (EPOCH FROM now() - pg_last_xact_replay_timestamp()) END AS lag_seconds;\" \\
|| echo \"Could not check replication lag\""
      ]
    end

    private

    def config_file_path
      "/etc/postgresql/#{version}/main/postgresql.conf"
    end

    def data_directory_path
      "/var/lib/postgresql/#{version}/main"
    end
  end
end
