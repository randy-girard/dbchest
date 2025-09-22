class CloudInitService
  def initialize
  end

  def generate_user_data(node_id, is_replica = false)
    @node = Node.find(node_id)

    # Generate a shell script for LXC containers (which don't typically support cloud-init)
    generate_setup_script(is_replica)
  end

  private

  def generate_setup_script(is_replica)
    <<~SCRIPT
      #!/bin/bash
      set -e

      # Cleanup function
      cleanup() {
        log "Cleaning up on exit..."
        rm -f /tmp/dbchest_setup.sh
        rm -f /tmp/dbchest_wrapper.sh
        log "Cleanup completed"
      }

      # Set up cleanup trap for various exit scenarios
      trap cleanup EXIT INT TERM

      # Logging function
      log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/dbchest-setup.log
      }

      # Callback function
      callback() {
        #{callback_script_inline}
      }

      log "Starting DBChest node setup..."
      callback "configuring" "Starting PostgreSQL installation..."

      #{postgresql_install_script}

      #{is_replica ? replica_setup_commands : primary_setup_commands}

      callback "active" "Node is now active and ready"
      log "DBChest node setup completed successfully"

      # Clean up temporary files
      log "Cleaning up installation files..."
      rm -f /tmp/dbchest_setup.sh
      rm -f /tmp/dbchest_wrapper.sh

      log "DBChest setup cleanup completed"
    SCRIPT
  end

  def primary_setup_commands
    # Generate replication password for this primary node
    replication_password = @node.ensure_replication_password!
    
    <<~SCRIPT
      # Configure PostgreSQL for replication readiness
      log "Configuring PostgreSQL for replication readiness..."
      callback "configuring" "Configuring PostgreSQL for replication readiness..."

      # Configure PostgreSQL settings for replication
      echo "wal_level = replica" >> /etc/postgresql/*/main/postgresql.conf
      echo "max_wal_senders = 10" >> /etc/postgresql/*/main/postgresql.conf
      echo "max_replication_slots = 10" >> /etc/postgresql/*/main/postgresql.conf
      echo "archive_mode = on" >> /etc/postgresql/*/main/postgresql.conf
      echo "archive_command = 'test ! -f /var/lib/postgresql/archive/%f && cp %p /var/lib/postgresql/archive/%f'" >> /etc/postgresql/*/main/postgresql.conf
      echo "listen_addresses = '*'" >> /etc/postgresql/*/main/postgresql.conf

      # Create archive directory
      mkdir -p /var/lib/postgresql/archive
      chown postgres:postgres /var/lib/postgresql/archive

      # Start PostgreSQL
      log "Starting PostgreSQL service..."
      callback "configuring" "Starting PostgreSQL with replication configuration..."
      systemctl restart postgresql
      systemctl enable postgresql

      # Wait for PostgreSQL to start
      sleep 5
      
      # Wait for PostgreSQL to be ready
      for i in {1..12}; do
        if sudo -u postgres pg_isready -q; then
          log "PostgreSQL is ready (attempt $i/12)"
          break
        else
          log "PostgreSQL not ready yet (attempt $i/12), waiting 5 seconds..."
          if [ $i -eq 12 ]; then
            log "ERROR: PostgreSQL failed to start within 60 seconds"
            callback "error" "PostgreSQL failed to start up"
            exit 1
          fi
          sleep 5
        fi
      done

      log "Primary PostgreSQL configured for replication capability"
      callback "configuring" "Primary ready - replication user and access will be added when replicas are created"
      
      # Create sample database and table for testing
      sudo -u postgres psql -c "CREATE DATABASE dbchest_sample;" || log "Sample database may already exist"
      sudo -u postgres psql -d dbchest_sample -c "
        CREATE TABLE IF NOT EXISTS sample_data (
          id SERIAL PRIMARY KEY,
          name VARCHAR(100),
          created_at TIMESTAMP DEFAULT NOW()
        );
        INSERT INTO sample_data (name) VALUES ('Initial Data'), ('Sample Record');
      " || log "Sample data setup completed"

      log "Primary PostgreSQL configuration completed"
      callback "configuring" "Primary node ready for replication connections"
    SCRIPT
  end

  def replica_setup_commands
    primary_node = @node.parent_node

    # Safety check for primary node
    if primary_node.nil?
      Rails.logger.error "Replica node #{@node.id} has no parent node - cannot create replica"
      return <<~SCRIPT
        log "ERROR: No primary node configured for this replica"
        callback "error" "No primary node configured for this replica"
        exit 1
      SCRIPT
    end

    # Get primary node info - it should be available since primary exists before replica creation
    primary_ip = primary_node.get_ip_address
    if primary_ip.blank?
      Rails.logger.error "Primary node #{primary_node.id} has no IP address - cannot create replica"
      return <<~SCRIPT
        log "ERROR: Primary node IP not available"
        callback "error" "Primary node IP address not available for replication setup"
        exit 1
      SCRIPT
    end

    replication_password = primary_node.ensure_replication_password!
    replica_node_name = @node.name
    slot_name = @node.name.downcase.gsub(/[^a-z0-9_]/, '_')

    <<~SCRIPT
      # Full replica setup including replication configuration
      log "Configuring replica to follow primary node at #{primary_ip}..."
      callback "configuring" "Configuring replication from primary at #{primary_ip}..."

      # Stop PostgreSQL if it's running
      systemctl stop postgresql || true

            # Clear existing data directory
      systemctl stop postgresql
      rm -rf /var/lib/postgresql/*/main/*

      # Test connectivity to primary before proceeding
      log "Testing connection to primary #{primary_ip}..."
      callback "configuring" "Testing connection to primary database..."
      
      if ! nc -z #{primary_ip} 5432; then
        log "ERROR: Cannot reach primary PostgreSQL at #{primary_ip}:5432"
        callback "error" "Cannot connect to primary database at #{primary_ip}:5432"
        exit 1
      fi
      
      log "Primary is reachable, proceeding with replication setup..."
      
      # Set up .pgpass file for replication user BEFORE testing connection
      log "Setting up replication credentials..."
      sudo -u postgres bash -c "echo '#{primary_ip}:5432:*:replication:#{replication_password}' > /var/lib/postgresql/.pgpass"
      sudo -u postgres chmod 600 /var/lib/postgresql/.pgpass
      log "Replication credentials configured in .pgpass file"
      
      # Primary should already be configured for replication by this point
      # Test replication connection to make sure it's working
      log "Testing replication connection to primary..."
      callback "configuring" "Testing replication connection to primary..."
      
      for i in {1..12}; do
        log "Testing replication connection (attempt $i/12)..."
        # Change to postgres home directory to avoid permission denied error
        if sudo -u postgres bash -c "cd /var/lib/postgresql && psql -h #{primary_ip} -U replication -d postgres -c 'SELECT 1;'" >/dev/null 2>&1; then
          log "Replication connection successful!"
          callback "configuring" "Primary configured - replication connection verified"
          break
        else
          if [ $i -eq 12 ]; then
            log "ERROR: Cannot connect to primary for replication after 2 minutes"
            callback "error" "Cannot connect to primary for replication"
            exit 1
          fi
          log "Replication connection not ready, waiting 10 seconds..."
          sleep 10
        fi
      done

      # Create base backup from primary
      log "Creating base backup from primary #{primary_ip}..."
      callback "configuring" "Creating base backup from primary..."

      # Create base backup with progress monitoring
      # Find the PostgreSQL version directory dynamically
      PG_VERSION=$(ls /var/lib/postgresql/ | grep -E '^[0-9]+$' | head -1)

      log "Starting pg_basebackup from primary..."
      callback "configuring" "Starting pg_basebackup - initializing backup..."

      # Run pg_basebackup with progress monitoring from the postgres home directory
      # Note: Removed -W flag to use .pgpass file instead of prompting for password
      sudo -u postgres bash -c "cd /var/lib/postgresql && pg_basebackup -h #{primary_ip} -D /var/lib/postgresql/$PG_VERSION/main -U replication -v -P -R" 2>&1 | while IFS= read -r line; do
        log "pg_basebackup: $line"
        
        # Send ALL output to frontend for debugging - we'll filter later
        callback "configuring" "pg_basebackup: $line"

        # Simplified parsing - just detect backup completion
        if echo "$line" | grep -q "backup complete"; then
          callback "configuring" "Backup complete - finalizing replica setup..."
        fi
      done

      # Check if pg_basebackup completed successfully
      if [ ${PIPESTATUS[0]} -ne 0 ]; then
        log "ERROR: pg_basebackup failed"
        callback "error" "Base backup from primary failed"
        exit 1
      fi

      log "Base backup completed successfully"
      callback "configuring" "Base backup completed - setting up replication configuration..."

      # Set up recovery configuration
      log "Setting up replication configuration..."
      callback "configuring" "Configuring replica connection to primary..."

      # The -R flag above should create postgresql.auto.conf with standby settings
      # But let's ensure the replica configuration is correct
      PG_VERSION=$(ls /var/lib/postgresql/ | grep -E '^[0-9]+$' | head -1)
      sudo -u postgres bash -c "cat >> /var/lib/postgresql/$PG_VERSION/main/postgresql.auto.conf << EOF
primary_conninfo = 'host=#{primary_ip} port=5432 user=replication password=#{replication_password} application_name=#{replica_node_name}'
primary_slot_name = '#{slot_name}'
EOF"

      log "Setting file permissions for PostgreSQL data directory..."
      callback "configuring" "Setting proper file permissions..."

      # Set proper ownership
      chown -R postgres:postgres /var/lib/postgresql/$PG_VERSION/main
      chmod 700 /var/lib/postgresql/$PG_VERSION/main

      # Start PostgreSQL as replica
      log "Starting PostgreSQL replica..."
      callback "configuring" "Starting PostgreSQL replica..."
      systemctl start postgresql
      systemctl enable postgresql

      # Wait for PostgreSQL to start up completely
      callback "configuring" "Waiting for PostgreSQL to start up..."
      log "Waiting for PostgreSQL startup..."
      sleep 5

      # Give it more time and check if it's running
      for i in {1..12}; do
        if sudo -u postgres pg_isready -q; then
          log "PostgreSQL is ready (attempt $i/12)"
          callback "configuring" "PostgreSQL is ready - verifying replication..."
          break
        else
          log "PostgreSQL not ready yet (attempt $i/12), waiting 5 seconds..."
          if [ $i -eq 12 ]; then
            log "ERROR: PostgreSQL failed to start within 60 seconds"
            callback "error" "PostgreSQL failed to start up"
            exit 1
          fi
          sleep 5
        fi
      done

      # Verify replication status
      log "Verifying replication status..."
      callback "configuring" "Checking if replica is in recovery mode..."

      if sudo -u postgres psql -c "SELECT pg_is_in_recovery();" | grep -q "t"; then
        log "Replica is successfully in recovery mode"
        callback "configuring" "Replica is in recovery mode - checking replication connection..."

        # Additional verification: check if we can see the primary in pg_stat_wal_receiver
        if sudo -u postgres psql -c "SELECT count(*) FROM pg_stat_wal_receiver;" | grep -q "1"; then
          log "Replication connection is active"
          callback "configuring" "Replication connection established successfully"
        else
          log "WARNING: No active WAL receiver found - replication may not be working"
          callback "configuring" "WARNING: Replication connection not yet established"
        fi
      else
        log "ERROR: Replica is not in recovery mode"
        callback "error" "Replica failed to enter recovery mode"
        exit 1
      fi

      # Final status check with replication lag information
      log "Getting replication status information..."
      callback "configuring" "Gathering replication status information..."
      
      # Get replication lag information if available
      lag_info=$(sudo -u postgres psql -t -c "SELECT CASE WHEN pg_is_in_recovery() THEN COALESCE(EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::int, 0) ELSE NULL END AS lag_seconds;" 2>/dev/null | xargs)
      
      if [ -n "$lag_info" ] && [ "$lag_info" != "" ]; then
        if [ "$lag_info" -eq 0 ]; then
          callback "configuring" "Replica is fully synchronized (lag: 0 seconds)"
        else
          callback "configuring" "Replica synchronized with $lag_info seconds lag"
        fi
      else
        callback "configuring" "Replica synchronization status: Unknown"
      fi
      
      log "Replica setup completed successfully"
    SCRIPT
  end

  def postgresql_install_script
    <<~SCRIPT
      # Install PostgreSQL
      log "Installing basic dependencies..."
      callback "configuring" "Installing basic dependencies..."

      # First install basic tools needed for setup
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget gnupg lsb-release ca-certificates netcat-openbsd

      log "Installing PostgreSQL..."
      callback "configuring" "Installing PostgreSQL..."

      # For Ubuntu 20.04 (focal), use default repositories with PostgreSQL 12/13
      # This is more reliable than the PostgreSQL APT repository which doesn't support focal
      log "Updating package lists..."
      callback "configuring" "Updating package lists..."
      apt-get update

      log "Installing PostgreSQL from Ubuntu repositories..."
      callback "configuring" "Installing PostgreSQL and dependencies..."
      DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-contrib python3-psycopg2

      log "Configuring PostgreSQL..."
      callback "configuring" "Configuring PostgreSQL..."

      # Set postgres user password (generate a random one)
      POSTGRES_PASSWORD=$(openssl rand -base64 32)
      sudo -u postgres psql -c "ALTER USER postgres PASSWORD '$POSTGRES_PASSWORD';"

      # Save password for later use
      echo "$POSTGRES_PASSWORD" > /var/lib/postgresql/.dbchest_password
      chown postgres:postgres /var/lib/postgresql/.dbchest_password
      chmod 600 /var/lib/postgresql/.dbchest_password

      # Configure PostgreSQL to listen on all addresses
      sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/*/main/postgresql.conf

      log "PostgreSQL installation completed"
    SCRIPT
  end

  def callback_script_inline
    callback_url = Rails.application.routes.url_helpers.node_status_callback_url(@node.id, host: callback_host)

    <<~SCRIPT
      local status="$1"
      local message="$2"

      # Escape JSON special characters in the message
      escaped_message=$(echo "$message" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g; s/\\t/\\\\t/g; s/\\n/\\\\n/g; s/\\r/\\\\r/g')

      # Check if curl is available before trying to use it
      if command -v curl >/dev/null 2>&1; then
        curl -X POST "#{callback_url}" \\
          -H "Content-Type: application/json" \\
          -d "{\\"status\\": \\"$status\\", \\"message\\": \\"$escaped_message\\"}" \\
          --max-time 10 \\
          --retry 3 \\
          --silent || log "Failed to send callback for status: $status"
      else
        log "Callback skipped - curl not available yet (status: $status, message: $escaped_message)"
      fi
    SCRIPT
  end



  def callback_host
    # Get the application host - in production this should be your actual domain
    # For local development, we need to use the host that the container can reach
    if Rails.env.production?
      ENV['APPLICATION_HOST'] || 'localhost:3000'
    else
      # In development, containers might not be able to reach localhost
      # You might need to use host.docker.internal or the actual IP
      ENV['DBCHEST_CALLBACK_HOST'] || 'host.docker.internal:3000'
    end
  end
end
