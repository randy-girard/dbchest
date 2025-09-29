require_relative "../cloud_init_generators/cassandra_cloud_init_generator"

module DatabaseTypes
  class CassandraDatabaseType < BaseDatabaseType
    # Register this handler with the base class
    BaseDatabaseType.register("cassandra", self)

    def supports_logical_replication?
      # Cassandra uses a different replication model (multi-master)
      false
    end

    def supports_streaming_replication?
      # Cassandra has built-in replication through its ring architecture
      true
    end

    def generate_cloud_init_script(node, is_replica: false)
      CloudInitGenerators::CassandraCloudInitGenerator.new(self, node).generate(is_replica: is_replica)
    end

    def primary_configuration_commands
      [
        "echo 'cluster_name: \"#{cluster_name}\"' >> #{config_file_path}",
        "echo 'num_tokens: 256' >> #{config_file_path}",
        "echo 'seeds: \"#{seeds_list}\"' >> #{config_file_path}",
        "echo 'listen_address: #{listen_address}' >> #{config_file_path}",
        "echo 'rpc_address: 0.0.0.0' >> #{config_file_path}",
        "echo 'broadcast_rpc_address: #{listen_address}' >> #{config_file_path}",
        "echo 'endpoint_snitch: GossipingPropertyFileSnitch' >> #{config_file_path}",
        "echo 'auto_bootstrap: false' >> #{config_file_path}"
      ]
    end

    def replica_configuration_commands
      [
        "echo 'cluster_name: \"#{cluster_name}\"' >> #{config_file_path}",
        "echo 'num_tokens: 256' >> #{config_file_path}",
        "echo 'seeds: \"#{seeds_list}\"' >> #{config_file_path}",
        "echo 'listen_address: #{listen_address}' >> #{config_file_path}",
        "echo 'rpc_address: 0.0.0.0' >> #{config_file_path}",
        "echo 'broadcast_rpc_address: #{listen_address}' >> #{config_file_path}",
        "echo 'endpoint_snitch: GossipingPropertyFileSnitch' >> #{config_file_path}",
        "echo 'auto_bootstrap: true' >> #{config_file_path}"
      ]
    end

    def readiness_check_command
      "cqlsh -e 'DESCRIBE CLUSTER' #{listen_address} #{default_port}"
    end

    def create_sample_data_commands
      [
        "cqlsh #{listen_address} #{default_port} -e \"",
        "CREATE KEYSPACE IF NOT EXISTS dbchest_sample",
        "WITH REPLICATION = {",
        "  'class': 'SimpleStrategy',",
        "  'replication_factor': #{replication_factor}",
        "};\"",
        "",
        "cqlsh #{listen_address} #{default_port} -e \"",
        "USE dbchest_sample;",
        "CREATE TABLE IF NOT EXISTS sample_data (",
        "  id UUID PRIMARY KEY,",
        "  name TEXT,",
        "  created_at TIMESTAMP",
        ");\"",
        "",
        "cqlsh #{listen_address} #{default_port} -e \"",
        "USE dbchest_sample;",
        "INSERT INTO sample_data (id, name, created_at)",
        "VALUES (uuid(), 'Initial Data', toTimestamp(now()));",
        "INSERT INTO sample_data (id, name, created_at)",
        "VALUES (uuid(), 'Sample Record', toTimestamp(now()));\""
      ]
    end

    def recovery_check_command
      "nodetool status | grep -q 'UN'"
    end

    def replication_lag_check_commands
      [
        "nodetool netstats | grep 'Streaming' || echo 'No active streaming'",
        "nodetool compactionstats || echo 'No active compactions'"
      ]
    end

    # Cassandra-specific methods
    def cluster_name
      @cluster_name ||= database_type_version.database_type.slug == "cassandra" ?
        "dbchest_cluster" : "#{database_type_version.database_type.slug}_cluster"
    end

    def seeds_list
      # This would be populated with actual seed node IPs in a real implementation
      # For now, return localhost for single-node setup
      "127.0.0.1"
    end

    def listen_address
      # This would be the actual node IP address
      "127.0.0.1"
    end

    def replication_factor
      # Default replication factor
      1
    end

    def create_keyspace_command(keyspace_name, replication_factor = nil)
      rf = replication_factor || self.replication_factor
      "cqlsh #{listen_address} #{default_port} -e \"CREATE KEYSPACE IF NOT EXISTS #{keyspace_name} WITH REPLICATION = {'class': 'SimpleStrategy', 'replication_factor': #{rf}};\""
    end

    def drop_keyspace_command(keyspace_name)
      "cqlsh #{listen_address} #{default_port} -e \"DROP KEYSPACE IF EXISTS #{keyspace_name};\""
    end

    def backup_keyspace_command(keyspace_name, backup_path)
      "nodetool snapshot #{keyspace_name} -t #{Time.current.strftime('%Y%m%d_%H%M%S')}"
    end

    def restore_keyspace_command(keyspace_name, backup_path)
      "nodetool refresh #{keyspace_name}"
    end

    def node_status_command
      "nodetool status"
    end

    def node_info_command
      "nodetool info"
    end

    def repair_command(keyspace_name = nil)
      if keyspace_name
        "nodetool repair #{keyspace_name}"
      else
        "nodetool repair"
      end
    end

    def cleanup_command
      "nodetool cleanup"
    end

    def flush_command
      "nodetool flush"
    end

    # Override default playbook names for Cassandra
    def primary_playbook
      "create_node.yml"
    end

    def replica_playbook
      "add_node.yml"  # Cassandra adds nodes rather than configuring replicas
    end

    def cleanup_playbook
      "remove_node.yml"
    end

    def primary_replication_playbook
      "expand_cluster.yml"
    end

    private

    def config_file_path
      "/etc/cassandra/cassandra.yaml"
    end

    def data_directory_path
      "/var/lib/cassandra"
    end

    def log_directory_path
      "/var/log/cassandra"
    end
  end
end
