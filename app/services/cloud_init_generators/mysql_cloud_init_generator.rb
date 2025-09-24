require_relative "base_cloud_init_generator"

module CloudInitGenerators
  class MysqlCloudInitGenerator < BaseCloudInitGenerator
    protected

    def install_script
      version_num = database_type.version
      install_command = database_type.install_command

      <<~SCRIPT
        # Install Database
        log "Installing basic dependencies..."
        callback "configuring" "Installing basic dependencies..."

        # First install basic tools needed for setup
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget

        log "Installing MySQL #{version_num}..."
        callback "configuring" "Installing MySQL #{version_num}..."

        # Execute the install command from the database configuration
        if ! (
          #{install_command}
        ); then
          log "ERROR: MySQL #{version_num} installation failed"
          callback "error" "MySQL #{version_num} installation failed. Check system compatibility and requirements."
          exit 1
        fi

        log "Configuring MySQL..."
        callback "configuring" "Configuring MySQL..."

        # Set root password (generate a random one)
        MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
        mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';"

        # Save password for later use
        echo "$MYSQL_ROOT_PASSWORD" > /var/lib/mysql/.dbchest_password
        chown mysql:mysql /var/lib/mysql/.dbchest_password
        chmod 600 /var/lib/mysql/.dbchest_password

        log "MySQL #{version_num} installation completed successfully"
      SCRIPT
    end

    def primary_setup_commands
      replication_password = generate_replication_password

      <<~SCRIPT
        log "Configuring MySQL as primary node..."
        callback "configuring" "Setting up primary MySQL node..."

        #{database_type.primary_configuration_commands.join("\n")}

        # Start MySQL
        log "Starting MySQL service..."
        callback "configuring" "Starting MySQL with replication configuration..."
        systemctl restart mysql
        systemctl enable mysql

        # Wait for MySQL to start
        sleep 5

        #{wait_for_service_ready_commands}

        log "Primary MySQL configured for replication capability"
        callback "configuring" "Primary ready - replication user and access will be added when replicas are created"

        #{database_type.create_sample_data_commands.join("\n")}

        log "Primary MySQL configuration completed"
        callback "configuring" "Primary node ready for replication connections"
      SCRIPT
    end

    def replica_setup_commands
      primary_node = node.parent_node
      return "" unless primary_node

      primary_ip = primary_node.get_ip_address
      replication_password = primary_node.get_replication_password

      <<~SCRIPT
        log "Configuring MySQL as replica node..."
        callback "configuring" "Setting up MySQL replica..."

        primary_ip="#{primary_ip}"
        replication_password="#{replication_password}"

        if [[ -z "$primary_ip" ]]; then
          log "ERROR: Primary node IP address not found"
          callback "error" "Primary node IP address not available"
          exit 1
        fi

        if [[ -z "$replication_password" ]]; then
          log "ERROR: Replication password not found"
          callback "error" "Replication password not available"
          exit 1
        fi

        log "Primary IP: $primary_ip"

        # Configure replica-specific settings
        #{database_type.replica_configuration_commands.join("\n")}

        # Restart MySQL with new configuration
        log "Restarting MySQL with replica configuration..."
        callback "configuring" "Applying replica configuration..."
        systemctl restart mysql

        #{wait_for_service_ready_commands}

        # Set up replication connection
        log "Setting up replication connection..."
        callback "configuring" "Connecting to primary for replication..."

        mysql -e "
          CHANGE MASTER TO
            MASTER_HOST='$primary_ip',
            MASTER_USER='replication',
            MASTER_PASSWORD='$replication_password',
            MASTER_AUTO_POSITION=1;
          START SLAVE;
        "

        # Verify replication status
        log "Verifying replication status..."
        callback "configuring" "Checking replica status..."

        if #{database_type.recovery_check_command}; then
          log "Replica is successfully configured"
          callback "configuring" "Replica is ready and replicating from primary"

          # Check replication lag
          #{database_type.replication_lag_check_commands.join("\n")}

          log "MySQL replica setup completed successfully"
        else
          log "ERROR: Replica configuration failed"
          callback "error" "Replica configuration failed"
          exit 1
        fi
      SCRIPT
    end
  end
end
