module CloudInitGenerators
  class BaseCloudInitGenerator
    attr_reader :database_type, :node

    def initialize(database_type, node)
      @database_type = database_type
      @node = node
    end

    def generate(is_replica: false)
      # Use modular approach - combine modules with main script
      script_name = self.class.name.split("::").last.gsub("CloudInitGenerator", "").downcase

      # Read the modular main script
      main_script_path = Rails.root.join("lib", "cloud_init_scripts", "#{script_name}_modular.sh")

      # If modular script doesn't exist, fall back to complete script
      if File.exist?(main_script_path)
        generate_modular_script(script_name, is_replica: is_replica)
      else
        # Fallback to old approach for backward compatibility
        script_path = Rails.root.join("lib", "cloud_init_scripts", "#{script_name}_complete.sh")
        script_content = File.read(script_path)
        substitute_variables(script_content, is_replica: is_replica)
      end
    end

    protected

    def generate_modular_script(script_name, is_replica: false)
      # Read all module files
      modules_dir = Rails.root.join("lib", "cloud_init_scripts", "modules")
      common_module = File.read(modules_dir.join("common.sh"))
      version_compatibility_module = File.read(modules_dir.join("version_compatibility.sh"))
      database_module = File.read(modules_dir.join("#{script_name}.sh"))

      # Read main script
      main_script_path = Rails.root.join("lib", "cloud_init_scripts", "#{script_name}_modular.sh")
      main_script = File.read(main_script_path)

      # Combine into a single script with embedded modules
      combined_script = build_combined_script(common_module, version_compatibility_module, database_module, main_script)

      # Apply variable substitutions
      substitute_variables(combined_script, is_replica: is_replica)
    end

    def build_combined_script(common_module, version_compatibility_module, database_module, main_script)
      # Get the database type name from the class
      db_type_name = self.class.name.split("::").last.gsub("CloudInitGenerator", "").downcase

      <<~SCRIPT
        #!/bin/bash
        set -e

        # Write modules to temporary files for sourcing
        cat > /tmp/common.sh << 'COMMON_MODULE_EOF'
        #{common_module}
        COMMON_MODULE_EOF

        cat > /tmp/version_compatibility.sh << 'VERSION_COMPATIBILITY_MODULE_EOF'
        #{version_compatibility_module}
        VERSION_COMPATIBILITY_MODULE_EOF

        cat > /tmp/#{db_type_name}.sh << 'DATABASE_MODULE_EOF'
        #{database_module}
        DATABASE_MODULE_EOF

        # Make modules executable
        chmod +x /tmp/common.sh
        chmod +x /tmp/version_compatibility.sh
        chmod +x /tmp/#{db_type_name}.sh

        # Execute main script
        #{main_script.lines[2..-1].join}  # Skip shebang and set -e from main script
      SCRIPT
    end

    def substitute_variables(script, is_replica: false)
      script_content = script.dup

      # Replace callback URL
      script_content.gsub!("{{CALLBACK_URL}}", callback_url)

      # Replace root password
      script_content.gsub!("{{ROOT_PASSWORD}}", node.root_password || "")

      # Replace database version information
      if node.database_type_version
        script_content.gsub!("{{DB_VERSION}}", node.database_type_version.version)
        script_content.gsub!("{{INSTALL_COMMAND}}", node.database_type_version.install_command)
        script_content.gsub!("{{SERVICE_NAME}}", node.database_type_version.service_name)
      end

      # Replace metrics collection variables
      script_content.gsub!("{{DBCHEST_API_URL}}", metrics_api_base_url)
      script_content.gsub!("{{NODE_ID}}", node.id.to_s)
      script_content.gsub!("{{METRICS_API_KEY}}", node.ensure_metrics_api_key!)
      script_content.gsub!("{{METRICS_COLLECTOR_SCRIPT}}", metrics_collector_script_content)
      script_content.gsub!("{{METRICS_SERVICE}}", metrics_service_content)
      script_content.gsub!("{{METRICS_TIMER}}", metrics_timer_content)

      # Add replica-specific substitutions if needed
      if is_replica
        Rails.logger.debug "BaseCloudInitGenerator: Generating replica script for node #{node.id}"
        Rails.logger.debug "BaseCloudInitGenerator: Parent node ID: #{node.parent_node_id}"
        Rails.logger.debug "BaseCloudInitGenerator: Parent node: #{node.parent_node&.id}"

        # For replicas, get the replication password from the parent node
        replication_password = node.parent_node&.ensure_replication_password! || ""
        Rails.logger.debug "BaseCloudInitGenerator: Replication password length: #{replication_password.length}"
        script_content.gsub!("{{REPLICATION_PASSWORD}}", replication_password)

        # Add primary connection details for replicas
        if node.parent_node
          primary_ip = node.parent_node.get_ip_address || ""
          Rails.logger.debug "BaseCloudInitGenerator: Primary IP: '#{primary_ip}'"
          script_content.gsub!("{{PRIMARY_HOST}}", primary_ip)
        else
          Rails.logger.warn "BaseCloudInitGenerator: No parent node found for replica!"
          script_content.gsub!("{{PRIMARY_HOST}}", "")
        end
      else
        Rails.logger.debug "BaseCloudInitGenerator: Generating primary script for node #{node.id}"
        # For primary nodes, generate and use the replication password
        # This creates the replication user with the password for future replicas
        replication_password = node.ensure_replication_password!
        Rails.logger.debug "BaseCloudInitGenerator: Primary replication password length: #{replication_password.length}"
        script_content.gsub!("{{REPLICATION_PASSWORD}}", replication_password)
        # PRIMARY_HOST is empty for primary nodes (they don't connect to another primary)
        script_content.gsub!("{{PRIMARY_HOST}}", "")
      end

      script_content
    end

    def install_script
      raise NotImplementedError, "#{self.class} must implement #install_script"
    end

    def primary_setup_commands
      raise NotImplementedError, "#{self.class} must implement #primary_setup_commands"
    end

    def replica_setup_commands
      raise NotImplementedError, "#{self.class} must implement #replica_setup_commands"
    end

    def callback_script_inline
      <<~SCRIPT.strip
        # Callback function to update node status
        callback() {
          local status="$1"
          local message="$2"
        #{'  '}
          curl -X POST "#{callback_host}/nodes/#{node.id}/status_callback" \\
            -H "Content-Type: application/json" \\
            -d "{\\"status\\": \\"$status\\", \\"message\\": \\"$message\\"}" \\
            -s -o /dev/null || true
        }
      SCRIPT
    end

    # Metrics-related helper methods
    def metrics_api_base_url
      # Use the same logic as callback_url for consistency
      port = ENV["PORT"] || "3000"

      if Rails.env.development?
        # Try to get the host IP that the container can reach
        # This might be host.docker.internal for Docker Desktop or the actual IP
        ENV["DBCHEST_CALLBACK_HOST"] || "http://host.docker.internal:#{port}"
      else
        # In production, use the actual application URL
        Rails.application.routes.default_url_options[:host] || "http://localhost:#{port}"
      end
    end

    def metrics_collector_script_content
      script_path = Rails.root.join("lib", "cloud_init_scripts", "metrics_collector.sh")
      script_content = File.read(script_path)

      # Substitute variables in the metrics collector script
      script_content.gsub!("{{DBCHEST_API_URL}}", metrics_api_base_url)
      script_content.gsub!("{{NODE_ID}}", node.id.to_s)
      script_content.gsub!("{{METRICS_API_KEY}}", node.ensure_metrics_api_key!)

      script_content
    end

    def metrics_service_content
      service_path = Rails.root.join("lib", "cloud_init_scripts", "dbchest-metrics.service")
      File.read(service_path)
    end

    def metrics_timer_content
      timer_path = Rails.root.join("lib", "cloud_init_scripts", "dbchest-metrics.timer")
      File.read(timer_path)
    end

    def callback_url
      # Get the application host - in production this should be your actual domain
      # For local development, we need to use the host that the container can reach
      port = ENV["PORT"] || "3000"

      base_host = if Rails.env.development?
        # Try to get the host IP that the container can reach
        # This might be host.docker.internal for Docker Desktop or the actual IP
        ENV["DBCHEST_CALLBACK_HOST"] || "http://host.docker.internal:#{port}"
      else
        # In production, use the actual application URL
        Rails.application.routes.default_url_options[:host] || "http://localhost:#{port}"
      end

      "#{base_host}/nodes/#{node.id}/status_callback"
    end
  end
end
