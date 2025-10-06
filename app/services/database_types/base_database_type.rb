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

    # Determines if database users are automatically replicated to replica nodes
    # Returns true if users created on primary are automatically available on replicas
    # Returns false if users must be created manually on each node
    def users_replicate_automatically?
      # By default, streaming replication replicates users (PostgreSQL, MySQL)
      # Override in subclasses for databases with different behavior (MongoDB, Cassandra)
      supports_streaming_replication?
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

    # Configuration template methods
    def rendered_config(variables = {})
      database_type_version.rendered_config_template(variables)
    end

    def has_config_template?
      database_type_version.has_config_template?
    end

    def config_template_variables(node = nil)
      variables = database_type_version.default_template_variables

      if node
        variables.merge!({
          node_id: node.id,
          node_name: node.name,
          cluster_name: node.cluster.name,
          is_replica: node.replica?,
          is_primary: node.primary?
        })
      end

      variables
    end

    # Registry for database type handlers
    @handlers = {}

    def self.register(slug, handler_class)
      @handlers[slug.to_s] = handler_class
    end

    def self.for_database_type_version(database_type_version)
      slug = database_type_version.database_type.slug
      handler_class = @handlers[slug]

      if handler_class
        handler_class.new(database_type_version)
      else
        raise ArgumentError, "Unknown database type: #{slug}. Available types: #{@handlers.keys.join(', ')}"
      end
    end

    def self.registered_types
      @handlers.keys
    end

    def self.registry
      @handlers
    end
  end
end
