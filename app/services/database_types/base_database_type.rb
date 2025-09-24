module DatabaseTypes
  class BaseDatabaseType
    attr_reader :database_type_version

    def initialize(database_type_version)
      @database_type_version = database_type_version
    end

    # Accessor methods for database information
    def database_type
      database_type_version.database_type.slug
    end

    def version
      database_type_version.version
    end

    # Override in subclasses
    def supports_logical_replication?
      raise NotImplementedError, "#{self.class} must implement #supports_logical_replication?"
    end

    def supports_streaming_replication?
      raise NotImplementedError, "#{self.class} must implement #supports_streaming_replication?"
    end

    def replication_method_for_cross_version(target_version)
      # If versions are different and logical replication is supported, use logical
      # Otherwise use streaming if supported, else return nil (not supported)
      if database_type_version.version != target_version.version
        if supports_logical_replication? && target_version.supports_logical_replication?
          "logical"
        else
          nil
        end
      elsif supports_streaming_replication?
        "streaming"
      else
        nil
      end
    end

    def generate_cloud_init_script(node, is_replica: false)
      raise NotImplementedError, "#{self.class} must implement #generate_cloud_init_script"
    end

    def ansible_playbook_directory
      "lib/ansible/#{database_type_version.database_type.slug}"
    end

    def primary_playbook
      "create_node.yml"
    end

    def replica_playbook
      "configure_replica.yml"
    end

    def cleanup_playbook
      "cleanup_replica_config.yml"
    end

    def primary_replication_playbook
      "configure_primary_replication.yml"
    end

    def create_user_playbook
      "create_user.yml"
    end

    def destroy_user_playbook
      "destroy_user.yml"
    end

    # Default configuration methods that can be overridden
    def default_port
      database_type_version.default_port
    end

    def service_name
      database_type_version.service_name
    end

    def data_directory_pattern
      database_type_version.data_directory_pattern
    end

    def config_file_pattern
      database_type_version.config_file_pattern
    end

    def major_version
      database_type_version.major_version
    end

    def version
      database_type_version.version
    end

    def install_command
      database_type_version.install_command
    end

    # Template methods for configuration
    def primary_configuration_commands
      []
    end

    def replica_configuration_commands
      []
    end

    def service_commands
      {
        start: "systemctl start #{service_name}",
        stop: "systemctl stop #{service_name}",
        restart: "systemctl restart #{service_name}",
        enable: "systemctl enable #{service_name}",
        status: "systemctl status #{service_name}"
      }
    end

    def self.for_database_type_version(database_type_version)
      case database_type_version.database_type.slug
      when "postgresql"
        PostgresqlDatabaseType.new(database_type_version)
      when "mysql"
        MysqlDatabaseType.new(database_type_version)
      else
        raise ArgumentError, "Unknown database type: #{database_type_version.database_type.slug}"
      end
    end
  end
end
