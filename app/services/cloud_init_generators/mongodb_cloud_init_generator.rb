module CloudInitGenerators
  class MongodbCloudInitGenerator < BaseCloudInitGenerator
    def generate(is_replica: false)
      # MongoDB still uses the inline approach since it's more complex
      # But we'll make it more modular and add progress reporting
      script_parts = [
        shebang,
        common_functions,
        setup_metrics_collection, # Move metrics collection to the beginning
        update_system,
        install_mongodb,
        configure_mongodb(is_replica),
        start_mongodb_service,
        setup_replication(is_replica),
        create_sample_data,
        final_status_update
      ]

      script_parts.compact.join("\n\n")
    end

    private

    def common_functions
      <<~SCRIPT
        # Common functions for MongoDB setup
        log() {
          local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
          echo "$message" | tee -a /var/log/dbchest-setup.log
        }

        callback() {
          local status="$1"
          local message="$2"

          curl -s -X POST "#{callback_url}" \\
            -H "Content-Type: application/json" \\
            -d "{\\"status\\": \\"$status\\", \\"message\\": \\"$message\\"}" || true
        }

        # Simple progress reporter for MongoDB operations
        start_progress_reporter() {
          local operation_name="$1"

          {
            local elapsed=0
            local interval=10

            while true; do
              sleep $interval
              elapsed=$((elapsed + interval))

              if [ $elapsed -eq 10 ]; then
                callback "configuring" "$operation_name started..."
              elif [ $elapsed -eq 30 ]; then
                callback "configuring" "$operation_name in progress..."
              elif [ $((elapsed % 60)) -eq 0 ]; then
                local minutes=$((elapsed / 60))
                callback "configuring" "$operation_name running for ${minutes} minute(s)..."
              fi
            done
          } &

          echo $!
        }

        stop_progress_reporter() {
          local reporter_pid="$1"
          local operation_name="$2"
          local success="${3:-true}"

          if [ -n "$reporter_pid" ]; then
            kill "$reporter_pid" 2>/dev/null || true
          fi

          if [ "$success" = "true" ]; then
            log "$operation_name completed successfully"
            callback "configuring" "$operation_name completed successfully"
          else
            log "$operation_name failed"
            callback "error" "$operation_name failed"
          fi
        }
      SCRIPT
    end

    def install_mongodb
      <<~SCRIPT
        # Install essential packages first
        echo "Installing essential packages..."
        apt-get update -y
        apt-get install -y curl bc jq

        # Install MongoDB
        echo "Installing MongoDB #{database_type_handler.version}..."

        # Import MongoDB public GPG key
        curl -fsSL https://pgp.mongodb.com/server-#{database_type_handler.major_version}.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-#{database_type_handler.major_version}.gpg --dearmor

        # Add MongoDB repository
        echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-#{database_type_handler.major_version}.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/#{database_type_handler.major_version} multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-#{database_type_handler.major_version}.list

        # Update package list and install MongoDB
        apt-get update
        apt-get install -y mongodb-org=#{database_type_handler.version}* mongodb-org-database=#{database_type_handler.version}* mongodb-org-server=#{database_type_handler.version}* mongodb-org-mongos=#{database_type_handler.version}* mongodb-org-tools=#{database_type_handler.version}*

        # Hold MongoDB packages to prevent automatic updates
        apt-mark hold mongodb-org mongodb-org-database mongodb-org-server mongodb-org-mongos mongodb-org-tools
      SCRIPT
    end

    def configure_mongodb(is_replica)
      config_commands = is_replica ? 
        database_type_handler.replica_configuration_commands : 
        database_type_handler.primary_configuration_commands

      <<~SCRIPT
        # Configure MongoDB
        echo "Configuring MongoDB..."
        
        # Backup original config
        cp /etc/mongod.conf /etc/mongod.conf.backup
        
        # Apply configuration commands
        #{config_commands.join("\n")}
      SCRIPT
    end

    def start_mongodb_service
      <<~SCRIPT
        # Start and enable MongoDB service
        echo "Starting MongoDB service..."
        systemctl enable mongod
        systemctl start mongod
        
        # Wait for MongoDB to be ready
        echo "Waiting for MongoDB to be ready..."
        for i in {1..30}; do
          if #{database_type_handler.readiness_check_command}; then
            echo "MongoDB is ready!"
            break
          fi
          echo "Waiting for MongoDB... ($i/30)"
          sleep 2
        done
      SCRIPT
    end

    def setup_replication(is_replica)
      return unless database_type_handler.supports_logical_replication?

      if is_replica
        setup_replica_replication
      else
        setup_primary_replication
      end
    end

    def setup_primary_replication
      <<~SCRIPT
        # Initialize replica set for primary
        echo "Initializing MongoDB replica set..."
        sleep 5  # Give MongoDB time to fully start
        #{database_type_handler.initiate_replica_set_command}
        
        echo "MongoDB primary replica set initialized"
      SCRIPT
    end

    def setup_replica_replication
      primary_ip = node.parent_node&.get_ip_address
      return unless primary_ip

      <<~SCRIPT
        # Configure as replica member
        echo "Configuring MongoDB replica..."
        
        # Wait for primary to be available
        echo "Waiting for primary MongoDB at #{primary_ip}..."
        for i in {1..60}; do
          if mongosh --host #{primary_ip}:#{database_type_handler.default_port} --eval 'db.runCommand("ping")' --quiet; then
            echo "Primary MongoDB is available!"
            break
          fi
          echo "Waiting for primary... ($i/60)"
          sleep 5
        done
        
        echo "MongoDB replica configuration completed"
      SCRIPT
    end

    def create_sample_data
      return if node.replica?

      <<~SCRIPT
        # Create sample data (primary only)
        echo "Creating sample data..."
        sleep 2  # Give MongoDB time to be fully ready
        
        #{database_type_handler.create_sample_data_commands.join("\n")}
        
        echo "Sample data created successfully"
      SCRIPT
    end

    def setup_metrics_collection
      <<~SCRIPT
        # Setup metrics collection
        echo "Setting up metrics collection..."

        # Create metrics collector script
        cat > /usr/local/bin/dbchest-metrics-collector.sh << 'METRICS_SCRIPT_EOF'
        #{metrics_collector_script_content}
        METRICS_SCRIPT_EOF

        # Make script executable
        chmod +x /usr/local/bin/dbchest-metrics-collector.sh

        # Create systemd service
        cat > /etc/systemd/system/dbchest-metrics.service << 'SERVICE_EOF'
        #{metrics_service_content}
        SERVICE_EOF

        # Create systemd timer
        cat > /etc/systemd/system/dbchest-metrics.timer << 'TIMER_EOF'
        #{metrics_timer_content}
        TIMER_EOF

        # Reload systemd and enable the timer
        systemctl daemon-reload
        systemctl enable dbchest-metrics.timer
        systemctl start dbchest-metrics.timer

        echo "Metrics collection service installed and started"
      SCRIPT
    end

    def final_status_update
      <<~SCRIPT
        # Final status update
        echo "MongoDB #{node.replica? ? 'replica' : 'primary'} setup completed successfully!"

        # Log MongoDB status
        systemctl status mongod --no-pager

        # Log replica set status (if applicable)
        if #{database_type_handler.supports_logical_replication?}; then
          mongosh --eval 'rs.status()' --quiet || echo "Replica set not yet configured"
        fi
      SCRIPT
    end

    # Helper methods for metrics collection scripts
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
      File.read(Rails.root.join("lib", "cloud_init_scripts", "dbchest-metrics.service"))
    end

    def metrics_timer_content
      File.read(Rails.root.join("lib", "cloud_init_scripts", "dbchest-metrics.timer"))
    end

    def metrics_api_base_url
      # Use the same logic as the base generator for consistency
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
  end
end
