#!/bin/bash

# DBChest Cloud Init - PostgreSQL Module
# This module contains PostgreSQL-specific installation and configuration functions

# Install PostgreSQL
install_postgresql() {
  local db_version="$1"
  local service_name="$2"

  log "Installing PostgreSQL version $db_version..."
  callback "configuring" "Installing PostgreSQL $db_version..."

  # Execute the version-specific installation command
  {{INSTALL_COMMAND}}

  # Wait for PostgreSQL to be ready
  sleep 5

  # Store root password
  mkdir -p /var/lib/postgresql
  echo "{{ROOT_PASSWORD}}" > /var/lib/postgresql/.dbchest_password
  chown postgres:postgres /var/lib/postgresql/.dbchest_password
  chmod 600 /var/lib/postgresql/.dbchest_password

  log "PostgreSQL $db_version installed successfully"
}

# Configure PostgreSQL authentication
configure_postgresql_auth() {
  log "Configuring PostgreSQL authentication..."

  # Set postgres user password (using su to avoid sudo issues)
  if ! su - postgres -c "psql -c \"ALTER USER postgres PASSWORD '{{ROOT_PASSWORD}}'\""; then
    log "ERROR: Failed to set postgres user password"
    callback "error" "Failed to set postgres user password"
    exit 1
  fi

  log "PostgreSQL authentication configured"
}

# Configure PostgreSQL for replication (primary)
configure_postgresql_primary() {
  local db_version="$1"
  local service_name="$2"

  log "Configuring PostgreSQL as primary for replication..."
  callback "configuring" "Setting up PostgreSQL replication (primary)..."

  # Create replication user (using su to avoid sudo issues)
  su - postgres -c "psql -c \"CREATE USER replication REPLICATION LOGIN CONNECTION LIMIT 5 PASSWORD '{{REPLICATION_PASSWORD}}'\"" || true

  # Configure PostgreSQL for replication
  local pg_conf="/etc/postgresql/$db_version/main/postgresql.conf"
  local pg_hba="/etc/postgresql/$db_version/main/pg_hba.conf"

  # Backup original files
  cp "$pg_conf" "$pg_conf.backup"
  cp "$pg_hba" "$pg_hba.backup"

  # Basic configuration
  echo "listen_addresses = '*'" >> "$pg_conf"
  echo "port = 5432" >> "$pg_conf"
  echo "max_connections = 100" >> "$pg_conf"
  echo "shared_buffers = 128MB" >> "$pg_conf"
  echo "logging_collector = on" >> "$pg_conf"
  echo "log_directory = 'log'" >> "$pg_conf"
  echo "log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'" >> "$pg_conf"
  echo "log_statement = 'all'" >> "$pg_conf"

  # Replication configuration
  echo "wal_level = replica" >> "$pg_conf"
  echo "max_wal_senders = 3" >> "$pg_conf"
  #echo "wal_keep_size = 64MB" >> "$pg_conf"
  echo "hot_standby = on" >> "$pg_conf"

  # Configure pg_hba.conf for replication
  echo "host replication replication 0.0.0.0/0 md5" >> "$pg_hba"
  echo "host all all 0.0.0.0/0 md5" >> "$pg_hba"

  # Restart PostgreSQL to apply configuration
  log "Restarting PostgreSQL to apply configuration..."
  if ! systemctl restart "$service_name"; then
    log "ERROR: Failed to restart PostgreSQL service"
    callback "error" "Failed to restart PostgreSQL service"
    exit 1
  fi

  # Wait for PostgreSQL to be ready
  if ! wait_for_service "$service_name"; then
    log "ERROR: PostgreSQL failed to start after configuration"
    callback "error" "PostgreSQL failed to start after configuration"
    exit 1
  fi

  log "PostgreSQL primary configuration completed"
}

# Setup PostgreSQL replica
setup_postgresql_replica() {
  local db_version="$1"
  local service_name="$2"
  local primary_host="{{PRIMARY_HOST}}"
  local replication_password="{{REPLICATION_PASSWORD}}"
  local backup_timeout="1800"  # 30 minutes

  log "Setting up PostgreSQL replica from primary: $primary_host"
  callback "configuring" "Setting up PostgreSQL replica..."

  # Stop PostgreSQL service
  systemctl stop "$service_name" || true

  # Remove existing data directory and recreate with proper permissions
  rm -rf "/var/lib/postgresql/$db_version/main"
  mkdir -p "/var/lib/postgresql/$db_version/main"
  chown postgres:postgres "/var/lib/postgresql/$db_version/main"
  chmod 700 "/var/lib/postgresql/$db_version/main"

  # Start enhanced progress monitoring for base backup
  local backup_log="/tmp/pg_basebackup_output.log"

  # Start pg_basebackup in background with proper environment
  log "Starting base backup from primary with live progress monitoring..."

  # Set up environment and run pg_basebackup without sudo issues
  export PGPASSWORD="$replication_password"
  timeout $backup_timeout su - postgres -c "
    export PGPASSWORD='$replication_password'
    pg_basebackup -h '$primary_host' -D '/var/lib/postgresql/$db_version/main' -U replication -v -P -R --no-password
  " > "$backup_log" 2>&1 &

  local backup_pid=$!

  # Start specialized pg_basebackup progress monitor
  local monitor_pid=$(monitor_pg_basebackup_progress "$backup_log" $backup_pid)

  # Wait for pg_basebackup to complete
  if wait $backup_pid; then
    # Stop the monitor
    kill $monitor_pid 2>/dev/null || true

    log "Base backup completed successfully"
    callback "configuring" "Base backup completed successfully (100%)"

    # Fix permissions on data directory after backup
    log "Setting correct permissions on PostgreSQL data directory..."
    chown -R postgres:postgres "/var/lib/postgresql/$db_version/main"
    chmod 700 "/var/lib/postgresql/$db_version/main"

    # Clean up
    rm -f "$backup_log"
  else
    # Stop the monitor
    kill $monitor_pid 2>/dev/null || true

    local backup_exit_code=$?
    log "ERROR: pg_basebackup failed with exit code $backup_exit_code"

    # Show last few lines for debugging
    if [ -f "$backup_log" ]; then
      log "Last output from pg_basebackup:"
      tail -5 "$backup_log" | while read line; do
        log "  $line"
      done
    fi

    callback "error" "Base backup failed - check node logs for details"
    rm -f "$backup_log"
    exit 1
  fi

  # Start PostgreSQL as replica
  log "Starting PostgreSQL replica..."
  callback "configuring" "Starting PostgreSQL replica..."
  systemctl start "$service_name"
  systemctl enable "$service_name"

  # Wait for PostgreSQL to start up completely
  if ! wait_for_service "$service_name"; then
    log "ERROR: PostgreSQL replica failed to start"
    callback "error" "PostgreSQL replica failed to start"
    exit 1
  fi

  # Verify replica is in recovery mode
  log "Verifying replication status..."
  callback "configuring" "Checking if replica is in recovery mode..."

  # Wait a bit more for the replica to enter recovery mode
  sleep 5

  # Check if we're in recovery mode (using su to avoid sudo issues)
  local in_recovery=$(su - postgres -c "psql -t -c 'SELECT pg_is_in_recovery();'" 2>/dev/null | tr -d ' \n' || echo "")

  if [ "$in_recovery" = "t" ]; then
    log "SUCCESS: PostgreSQL replica is in recovery mode"
    callback "configuring" "PostgreSQL replica is running and in recovery mode"
  else
    log "WARNING: PostgreSQL replica may not be in recovery mode (got: '$in_recovery')"
    callback "configuring" "PostgreSQL replica started but recovery status unclear"
  fi

  log "PostgreSQL replica setup completed"
}
