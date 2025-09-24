require_relative "../cloud_init_generators/mongodb_cloud_init_generator"

module DatabaseTypes
  class MongodbDatabaseType < BaseDatabaseType
    # Register this handler with the base class
    BaseDatabaseType.register('mongodb', self)

    def supports_logical_replication?
      # MongoDB supports replica sets from version 3.0+
      major_version >= 3
    end

    def supports_streaming_replication?
      # MongoDB replica sets provide streaming replication
      major_version >= 3
    end

    def generate_cloud_init_script(node, is_replica: false)
      CloudInitGenerators::MongodbCloudInitGenerator.new(self, node).generate(is_replica: is_replica)
    end

    def primary_configuration_commands
      [
        "echo 'replication:' >> #{config_file_path}",
        "echo '  replSetName: \"#{replica_set_name}\"' >> #{config_file_path}",
        "echo 'net:' >> #{config_file_path}",
        "echo '  bindIp: 0.0.0.0' >> #{config_file_path}",
        "echo '  port: #{default_port}' >> #{config_file_path}"
      ]
    end

    def replica_configuration_commands
      [
        "echo 'replication:' >> #{config_file_path}",
        "echo '  replSetName: \"#{replica_set_name}\"' >> #{config_file_path}",
        "echo 'net:' >> #{config_file_path}",
        "echo '  bindIp: 0.0.0.0' >> #{config_file_path}",
        "echo '  port: #{default_port}' >> #{config_file_path}"
      ]
    end

    def readiness_check_command
      "mongosh --eval 'db.runCommand(\"ping\")' --quiet"
    end

    def create_sample_data_commands
      [
        "mongosh --eval 'use dbchest_sample'",
        "mongosh dbchest_sample --eval '",
        "  db.sample_data.insertMany([",
        "    { name: \"Initial Data\", created_at: new Date() },",
        "    { name: \"Sample Record\", created_at: new Date() }",
        "  ])",
        "'"
      ]
    end

    def recovery_check_command
      "mongosh --eval 'rs.isMaster().ismaster' --quiet | grep -q 'false'"
    end

    def replication_lag_check_commands
      [
        "mongosh --eval 'rs.printSlaveReplicationInfo()' --quiet || echo 'Could not check replication lag'"
      ]
    end

    # MongoDB-specific methods
    def replica_set_name
      "dbchest_rs"
    end

    def initiate_replica_set_command
      "mongosh --eval 'rs.initiate()'"
    end

    def add_replica_member_command(replica_ip)
      "mongosh --eval 'rs.add(\"#{replica_ip}:#{default_port}\")'"
    end

    private

    def config_file_path
      "/etc/mongod.conf"
    end

    def data_directory_path
      "/var/lib/mongodb"
    end
  end
end
