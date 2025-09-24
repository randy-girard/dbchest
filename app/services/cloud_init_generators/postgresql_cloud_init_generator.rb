require_relative "base_cloud_init_generator"

module CloudInitGenerators
  class PostgresqlCloudInitGenerator < BaseCloudInitGenerator
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
        DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget gnupg2 lsb-release

        log "Installing PostgreSQL #{version_num}..."
        callback "configuring" "Installing PostgreSQL #{version_num}..."

        # Execute the install command from the database configuration
        if ! (
          #{install_command}
        ); then
          log "ERROR: PostgreSQL #{version_num} installation failed"
          callback "error" "PostgreSQL #{version_num} installation failed. Check system compatibility and requirements."
          exit 1
        fi

        # Install additional dependencies
        DEBIAN_FRONTEND=noninteractive apt-get install -y python3-psycopg2

        log "Configuring PostgreSQL..."
        callback "configuring" "Configuring PostgreSQL..."

        # Verify the expected version was installed
        if [[ ! -d "/etc/postgresql/#{version_num}" ]]; then
          log "ERROR: PostgreSQL #{version_num} was not installed properly"
          callback "error" "PostgreSQL #{version_num} installation failed - version directory not found"
          exit 1
        fi

        # Set postgres user password (generate a random one)
        POSTGRES_PASSWORD=$(openssl rand -base64 32)
        sudo -u postgres psql -c "ALTER USER postgres PASSWORD '$POSTGRES_PASSWORD';"

        # Save password for later use
        echo "$POSTGRES_PASSWORD" > /var/lib/postgresql/.dbchest_password
        chown postgres:postgres /var/lib/postgresql/.dbchest_password
        chmod 600 /var/lib/postgresql/.dbchest_password

        # Configure PostgreSQL to listen on all addresses (using expected version)
        sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/#{version_num}/main/postgresql.conf

        log "PostgreSQL #{version_num} installation completed successfully"
      SCRIPT
    end

    def primary_setup_commands
      version_num = database_type.version
      replication_password = generate_replication_password

      <<~SCRIPT
        log "Configuring PostgreSQL as primary node..."
        callback "configuring" "Setting up primary PostgreSQL node..."

        #{database_type.primary_configuration_commands.join("\n")}

        # Start PostgreSQL
        log "Starting PostgreSQL service..."
        callback "configuring" "Starting PostgreSQL with replication configuration..."
        systemctl restart postgresql
        systemctl enable postgresql

        # Wait for PostgreSQL to start
        sleep 5

        #{wait_for_service_ready_commands}

        log "Primary PostgreSQL configured for replication capability"
        callback "configuring" "Primary ready - replication user and access will be added when replicas are created"

        #{database_type.create_sample_data_commands.join("\n")}

        log "Primary PostgreSQL configuration completed"
        callback "configuring" "Primary node ready for replication connections"
      SCRIPT
    end

    def replica_setup_commands
      primary_node = node.parent_node
      return "" unless primary_node

      version_num = database_type.version
      primary_ip = primary_node.get_ip_address
      replication_password = primary_node.get_replication_password
      replica_node_name = node.name.downcase.gsub(/[^a-z0-9]/, "-")
      slot_name = "#{replica_node_name}_slot"

      <<~SCRIPT
        log "Configuring PostgreSQL as replica node..."
        callback "configuring" "Setting up PostgreSQL replica..."

        primary_ip="#{primary_ip}"
        replication_password="#{replication_password}"
        replica_version="#{version_num}"
        replica_node_name="#{replica_node_name}"
        slot_name="#{slot_name}"

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
        log "Replica version: $replica_version"

        # Stop PostgreSQL before configuring replica
        log "Stopping PostgreSQL for replica configuration..."
        callback "configuring" "Preparing for replica setup..."
        systemctl stop postgresql

        # Remove existing data directory and recreate
        log "Preparing data directory for base backup..."
        callback "configuring" "Clearing data directory for base backup..."
        rm -rf /var/lib/postgresql/$replica_version/main/*

        # Take base backup from primary
        log "Taking base backup from primary..."
        callback "configuring" "Downloading base backup from primary ($primary_ip)..."

        sudo -u postgres PGPASSWORD="$replication_password" pg_basebackup \\
          -h "$primary_ip" \\
          -D "/var/lib/postgresql/$replica_version/main" \\
          -U replication \\
          -v \\
          -P \\
          -W \\
          -R

        # Ensure proper configuration for replica
        log "Configuring replica settings..."
        callback "configuring" "Setting up replica configuration..."

        # Add replica-specific configuration
        #{database_type.replica_configuration_commands.join("\n")}

        # Configure recovery settings (PostgreSQL 12+ uses postgresql.auto.conf for these)
        # Split the long primary_conninfo into multiple variables for readability
        CONFIG_FILE="/var/lib/postgresql/$replica_version/main/postgresql.auto.conf"
        PRIMARY_CONN="host=#{primary_ip} port=5432 user=replication"
        PRIMARY_CONN="$PRIMARY_CONN password=#{replication_password}"
        PRIMARY_CONN="$PRIMARY_CONN application_name=#{replica_node_name}"

        echo "primary_conninfo = '$PRIMARY_CONN'" | sudo -u postgres tee $CONFIG_FILE > /dev/null
        echo "primary_slot_name = '#{slot_name}'" | sudo -u postgres tee -a $CONFIG_FILE > /dev/null

        log "Setting file permissions for PostgreSQL data directory..."
        callback "configuring" "Setting proper file permissions..."

        # Set proper ownership
        chown -R postgres:postgres /var/lib/postgresql/$replica_version/main
        chmod 700 /var/lib/postgresql/$replica_version/main

        # Start PostgreSQL as replica
        log "Starting PostgreSQL replica..."
        callback "configuring" "Starting PostgreSQL replica..."
        systemctl start postgresql
        systemctl enable postgresql

        # Wait for PostgreSQL to start up completely
        callback "configuring" "Waiting for PostgreSQL to start up..."
        log "Waiting for PostgreSQL startup..."
        sleep 5

        #{wait_for_service_ready_commands}

        # Verify replication status
        log "Verifying replication status..."
        callback "configuring" "Checking if replica is in recovery mode..."

        if #{database_type.recovery_check_command}; then
          log "Replica is successfully in recovery mode"
          callback "configuring" "Replica is in recovery mode - checking replication connection..."

          # Check replication lag
          #{database_type.replication_lag_check_commands.join("\n")}

          log "PostgreSQL replica setup completed successfully"
          callback "configuring" "Replica is ready and replicating from primary"
        else
          log "ERROR: Replica is not in recovery mode"
          callback "error" "Replica configuration failed - not in recovery mode"
          exit 1
        fi
      SCRIPT
    end
  end
end
