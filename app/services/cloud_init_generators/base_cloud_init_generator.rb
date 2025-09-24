module CloudInitGenerators
  class BaseCloudInitGenerator
    attr_reader :database_type, :node

    def initialize(database_type, node)
      @database_type = database_type
      @node = node
    end

    def generate(is_replica: false)
      # Read the complete database-specific cloud-init script
      script_name = self.class.name.split('::').last.gsub('CloudInitGenerator', '').downcase
      script_path = Rails.root.join('lib', 'cloud_init_scripts', "#{script_name}_complete.sh")
      script_content = File.read(script_path)
      
      # Create a customized version in the terraform working directory
      substitute_variables(script_content, is_replica: is_replica)
    end

    protected

    def substitute_variables(script, is_replica: false)
      script_content = script.dup
      
      # Replace callback URL
      script_content.gsub!('{{CALLBACK_URL}}', callback_url)
      
      # Replace root password 
      script_content.gsub!('{{ROOT_PASSWORD}}', node.root_password || '')
      
      # Replace database version information
      if node.database_type_version
        script_content.gsub!('{{DB_VERSION}}', node.database_type_version.version)
        script_content.gsub!('{{INSTALL_COMMAND}}', node.database_type_version.install_command)
        script_content.gsub!('{{SERVICE_NAME}}', node.database_type_version.service_name)
      end
      
      # Add replica-specific substitutions if needed
      if is_replica
        Rails.logger.debug "BaseCloudInitGenerator: Generating replica script for node #{node.id}"
        Rails.logger.debug "BaseCloudInitGenerator: Parent node ID: #{node.parent_node_id}"
        Rails.logger.debug "BaseCloudInitGenerator: Parent node: #{node.parent_node&.id}"
        
        # For replicas, get the replication password from the parent node
        replication_password = node.parent_node&.ensure_replication_password! || ''
        Rails.logger.debug "BaseCloudInitGenerator: Replication password length: #{replication_password.length}"
        script_content.gsub!('{{REPLICATION_PASSWORD}}', replication_password)
        
        # Add primary connection details for replicas
        if node.parent_node
          primary_ip = node.parent_node.get_ip_address || ''
          Rails.logger.debug "BaseCloudInitGenerator: Primary IP: '#{primary_ip}'"
          script_content.gsub!('{{PRIMARY_HOST}}', primary_ip)
        else
          Rails.logger.warn "BaseCloudInitGenerator: No parent node found for replica!"
          script_content.gsub!('{{PRIMARY_HOST}}', '')
        end
      else
        Rails.logger.debug "BaseCloudInitGenerator: Generating primary script for node #{node.id}"
        # For primary nodes, ensure replica variables are empty
        script_content.gsub!('{{REPLICATION_PASSWORD}}', '')
        script_content.gsub!('{{PRIMARY_HOST}}', '')
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
          
          curl -X POST "#{callback_host}/nodes/#{node.id}/status_callback" \\
            -H "Content-Type: application/json" \\
            -d "{\\"status\\": \\"$status\\", \\"message\\": \\"$message\\"}" \\
            -s -o /dev/null || true
        }
      SCRIPT
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
