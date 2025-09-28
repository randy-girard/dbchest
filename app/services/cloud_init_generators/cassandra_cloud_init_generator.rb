module CloudInitGenerators
  class CassandraCloudInitGenerator < BaseCloudInitGenerator
    def generate(is_replica: false)
      # Cassandra uses a modular approach with progress reporting
      script_parts = [
        shebang,
        common_functions,
        setup_metrics_collection,
        update_system,
        install_cassandra,
        configure_cassandra(is_replica),
        start_cassandra_service,
        setup_cluster(is_replica),
        create_sample_data,
        final_status_update
      ]

      script_parts.compact.join("\n\n")
    end

    private

    def common_functions
      <<~SCRIPT
        # Common functions for Cassandra setup
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

        # Progress reporter for Cassandra operations
        start_progress_reporter() {
          local operation_name="$1"

          {
            local elapsed=0
            local interval=15

            while true; do
              sleep $interval
              elapsed=$((elapsed + interval))

              if [ $elapsed -eq 15 ]; then
                callback "configuring" "$operation_name started..."
              elif [ $elapsed -eq 45 ]; then
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

    def install_cassandra
      <<~SCRIPT
        # Install essential packages first
        echo "Installing essential packages..."
        apt-get update -y
        apt-get install -y curl bc jq openjdk-8-jdk

        # Set JAVA_HOME
        export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
        echo 'export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64' >> /etc/environment

        # Install Cassandra
        echo "Installing Apache Cassandra #{database_type_handler.version}..."

        # Add Cassandra repository key
        curl -fsSL https://downloads.apache.org/cassandra/KEYS | sudo apt-key add -

        # Add Cassandra repository
        echo "deb https://downloads.apache.org/cassandra/debian #{database_type_handler.major_version}x main" | sudo tee -a /etc/apt/sources.list.d/cassandra.sources.list

        # Update package list and install Cassandra
        apt-get update
        apt-get install -y cassandra=#{database_type_handler.version}*

        # Hold Cassandra packages to prevent automatic updates
        apt-mark hold cassandra

        # Install Cassandra tools
        apt-get install -y cassandra-tools
      SCRIPT
    end

    def configure_cassandra(is_replica)
      config_commands = is_replica ?
        database_type_handler.replica_configuration_commands :
        database_type_handler.primary_configuration_commands

      <<~SCRIPT
        # Configure Cassandra
        echo "Configuring Cassandra..."

        # Stop Cassandra service for configuration
        systemctl stop cassandra

        # Backup original config
        cp /etc/cassandra/cassandra.yaml /etc/cassandra/cassandra.yaml.backup

        # Clear existing configuration
        > /etc/cassandra/cassandra.yaml

        # Apply configuration commands
        #{config_commands.join("\n")}

        # Set proper ownership
        chown cassandra:cassandra /etc/cassandra/cassandra.yaml
        chown -R cassandra:cassandra /var/lib/cassandra
        chown -R cassandra:cassandra /var/log/cassandra

        # Configure JVM options
        echo "Configuring JVM options..."
        cat > /etc/cassandra/jvm.options << 'JVM_EOF'
        -Xms1G
        -Xmx1G
        -XX:+UseG1GC
        -XX:G1RSetUpdatingPauseTimePercent=5
        -XX:MaxGCPauseMillis=300
        -XX:InitiatingHeapOccupancyPercent=70
        -Djava.net.preferIPv4Stack=true
        JVM_EOF
      SCRIPT
    end

    def start_cassandra_service
      <<~SCRIPT
        # Start and enable Cassandra service
        echo "Starting Cassandra service..."
        systemctl enable cassandra
        systemctl start cassandra

        # Wait for Cassandra to be ready
        echo "Waiting for Cassandra to be ready..."
        for i in {1..60}; do
          if #{database_type_handler.readiness_check_command} 2>/dev/null; then
            echo "Cassandra is ready!"
            break
          fi
          echo "Waiting for Cassandra... ($i/60)"
          sleep 5
        done

        # Check if Cassandra started successfully
        if ! systemctl is-active --quiet cassandra; then
          echo "ERROR: Cassandra failed to start"
          systemctl status cassandra
          exit 1
        fi
      SCRIPT
    end

    def setup_cluster(is_replica)
      if is_replica
        setup_node_join
      else
        setup_primary_node
      end
    end

    def setup_primary_node
      <<~SCRIPT
        # Initialize Cassandra cluster (primary node)
        echo "Initializing Cassandra cluster..."
        sleep 10  # Give Cassandra time to fully start

        # Check cluster status
        #{database_type_handler.node_status_command}

        echo "Cassandra primary node initialized"
      SCRIPT
    end

    def setup_node_join
      <<~SCRIPT
        # Join Cassandra cluster (additional node)
        echo "Joining Cassandra cluster..."

        # Wait for seed nodes to be available
        echo "Waiting for seed nodes to be available..."
        for i in {1..30}; do
          if #{database_type_handler.readiness_check_command} 2>/dev/null; then
            echo "Seed nodes are available!"
            break
          fi
          echo "Waiting for seed nodes... ($i/30)"
          sleep 10
        done

        # Check cluster status
        #{database_type_handler.node_status_command}

        echo "Node successfully joined Cassandra cluster"
      SCRIPT
    end

    def create_sample_data
      return if node.replica?

      <<~SCRIPT
        # Create sample data (primary only)
        echo "Creating sample keyspace and data..."
        sleep 5  # Give Cassandra time to be fully ready

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
        echo "Cassandra #{node.replica? ? 'node' : 'primary'} setup completed successfully!"

        # Log Cassandra status
        systemctl status cassandra --no-pager

        # Log cluster status
        #{database_type_handler.node_status_command} || echo "Cluster status not yet available"

        # Log node info
        #{database_type_handler.node_info_command} || echo "Node info not yet available"

        callback "active" "Cassandra setup completed successfully"
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
        ENV["DBCHEST_CALLBACK_HOST"] || "http://host.docker.internal:#{port}"
      else
        # In production, use the actual application URL
        Rails.application.routes.default_url_options[:host] || "http://localhost:#{port}"
      end
    end
  end
end
