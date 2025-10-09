#!/bin/bash

# DBChest Cloud Init - MySQL Module
# This module contains MySQL-specific installation and configuration functions

# Install MySQL
install_mysql() {
  local db_version="$1"
  local service_name="$2"
  local ubuntu_version=$(lsb_release -rs)
  local ubuntu_codename=$(lsb_release -cs)

  log "Installing MySQL version $db_version..."
  log "System: Ubuntu $ubuntu_version ($ubuntu_codename)"
  log "Target: MySQL $db_version"
  callback "configuring" "Installing MySQL $db_version..."

  # Execute the version-specific installation command
  log "Running MySQL installation command..."
  if ! (
    {{INSTALL_COMMAND}}
  ); then
    log "ERROR: MySQL $db_version installation failed"
    log "ERROR: Installation aborted due to failure"
    callback "error" "MySQL $db_version installation failed. Check system compatibility and requirements."
    exit 1
  fi

  # Verify installation
  log "Verifying MySQL installation..."
  if ! command -v mysql >/dev/null 2>&1; then
    log "ERROR: MySQL $db_version installation failed - mysql command not found"
    log "Checking installed packages:"
    dpkg -l | grep mysql || true
    callback "error" "MySQL installation verification failed"
    exit 1
  fi

  # Wait for MySQL to be ready
  log "Waiting for MySQL to initialize..."
  sleep 5

  # Store root password securely
  log "Storing database credentials..."
  safe_exec mkdir -p /var/lib/mysql
  echo "{{ROOT_PASSWORD}}" > /var/lib/mysql/.dbchest_password
  safe_exec chown mysql:mysql /var/lib/mysql/.dbchest_password
  safe_exec chmod 600 /var/lib/mysql/.dbchest_password

  log "MySQL $db_version installed successfully on Ubuntu $ubuntu_version"
}

# Configure MySQL authentication
configure_mysql_auth() {
  log "Configuring MySQL authentication..."

  # Set root password (using password from file)
  log "Setting root user password..."
  if ! MYSQL_PWD="" mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '{{ROOT_PASSWORD}}';" 2>/dev/null; then
    # Try without MYSQL_PWD if first attempt fails
    if ! mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '{{ROOT_PASSWORD}}';" 2>/dev/null; then
      log "ERROR: Failed to set MySQL root password"
      log "Checking MySQL service status:"
      systemctl status mysql --no-pager || true
      log "Recent MySQL error log entries:"
      tail -20 /var/log/mysql/error.log 2>/dev/null || true
      callback "error" "Failed to configure MySQL authentication"
      exit 1
    fi
  fi

  log "MySQL authentication configured successfully"
}

# Configure MySQL for replication (primary)
configure_mysql_primary() {
  local db_version="$1"
  local service_name="$2"

  log "Configuring MySQL as primary for replication..."
  callback "configuring" "Setting up MySQL replication (primary)..."

  # Configure MySQL for remote connections
  local mysql_conf="/etc/mysql/mysql.conf.d/mysqld.cnf"

  # Verify config file exists
  if [ ! -f "$mysql_conf" ]; then
    log "ERROR: MySQL config file not found: $mysql_conf"
    log "Checking MySQL configuration directory:"
    ls -la /etc/mysql/ || true
    ls -la /etc/mysql/mysql.conf.d/ || true
    callback "error" "MySQL configuration file not found"
    exit 1
  fi

  # Backup configuration
  log "Backing up original configuration file..."
  safe_exec cp "$mysql_conf" "$mysql_conf.backup"

  # Basic configuration
  log "Applying basic MySQL configuration..."
  sed -i 's/bind-address.*/bind-address = 0.0.0.0/' "$mysql_conf"

  # Add configuration if not already present
  if ! grep -q "max_connections" "$mysql_conf"; then
    echo "max_connections = 100" >> "$mysql_conf"
  fi

  # Enable MySQL logging
  log "Enabling MySQL logging..."
  echo "log_error = /var/log/mysql/error.log" >> "$mysql_conf"
  echo "general_log = 1" >> "$mysql_conf"
  echo "general_log_file = /var/log/mysql/mysql.log" >> "$mysql_conf"
  echo "slow_query_log = 1" >> "$mysql_conf"
  echo "slow_query_log_file = /var/log/mysql/mysql-slow.log" >> "$mysql_conf"

  # Replication configuration
  log "Applying replication configuration..."
  echo "server-id = 1" >> "$mysql_conf"
  echo "log-bin = mysql-bin" >> "$mysql_conf"
  echo "binlog-format = ROW" >> "$mysql_conf"

  # Add GTID configuration for MySQL 5.6+
  echo "gtid-mode = ON" >> "$mysql_conf"
  echo "enforce-gtid-consistency = ON" >> "$mysql_conf"

  # Restart MySQL to apply configuration
  log "Restarting MySQL to apply configuration..."
  safe_exec systemctl restart "$service_name"
  safe_exec systemctl enable "$service_name"

  # Wait for MySQL to be ready
  log "Waiting for MySQL to be ready after restart..."
  if ! wait_for_service "$service_name"; then
    log "ERROR: MySQL failed to start after configuration"
    log "MySQL service status:"
    systemctl status "$service_name" --no-pager || true
    log "Recent MySQL error log entries:"
    tail -50 /var/log/mysql/error.log 2>/dev/null || true
    log "Recent journal entries:"
    journalctl -u "$service_name" -n 50 --no-pager || true
    callback "error" "MySQL failed to start after configuration - check logs"
    exit 1
  fi

  # Create replication user
  log "Creating replication user..."
  if ! MYSQL_PWD="{{ROOT_PASSWORD}}" mysql -u root -e "CREATE USER IF NOT EXISTS 'replication'@'%' IDENTIFIED BY '{{REPLICATION_PASSWORD}}';" 2>/dev/null; then
    log "ERROR: Failed to create replication user"
    log "Recent MySQL error log entries:"
    tail -20 /var/log/mysql/error.log 2>/dev/null || true
    callback "error" "Failed to create MySQL replication user"
    exit 1
  fi

  MYSQL_PWD="{{ROOT_PASSWORD}}" mysql -u root -e "GRANT REPLICATION SLAVE ON *.* TO 'replication'@'%';" || true
  MYSQL_PWD="{{ROOT_PASSWORD}}" mysql -u root -e "FLUSH PRIVILEGES;" || true

  log "MySQL primary configuration completed successfully"
}

# Setup MySQL replica
setup_mysql_replica() {
  local db_version="$1"
  local service_name="$2"
  local primary_host="{{PRIMARY_HOST}}"
  local replication_password="{{REPLICATION_PASSWORD}}"

  log "Setting up MySQL replica from primary: $primary_host"
  callback "configuring" "Setting up MySQL replica..."

  # Stop MySQL service
  log "Stopping MySQL service..."
  systemctl stop "$service_name" || true

  # Configure MySQL for replication
  local mysql_conf="/etc/mysql/mysql.conf.d/mysqld.cnf"

  # Verify config file exists
  if [ ! -f "$mysql_conf" ]; then
    log "ERROR: MySQL config file not found: $mysql_conf"
    log "Checking MySQL configuration directory:"
    ls -la /etc/mysql/ || true
    ls -la /etc/mysql/mysql.conf.d/ || true
    callback "error" "MySQL configuration file not found"
    exit 1
  fi

  # Backup configuration
  log "Backing up original configuration file..."
  safe_exec cp "$mysql_conf" "$mysql_conf.backup"

  # Basic configuration
  log "Applying basic MySQL configuration..."
  sed -i 's/bind-address.*/bind-address = 0.0.0.0/' "$mysql_conf"

  # Add configuration if not already present
  if ! grep -q "max_connections" "$mysql_conf"; then
    echo "max_connections = 100" >> "$mysql_conf"
  fi

  # Enable MySQL logging
  log "Enabling MySQL logging..."
  echo "log_error = /var/log/mysql/error.log" >> "$mysql_conf"
  echo "general_log = 1" >> "$mysql_conf"
  echo "general_log_file = /var/log/mysql/mysql.log" >> "$mysql_conf"
  echo "slow_query_log = 1" >> "$mysql_conf"
  echo "slow_query_log_file = /var/log/mysql/mysql-slow.log" >> "$mysql_conf"

  # Replica configuration
  log "Applying replica configuration..."
  echo "server-id = 2" >> "$mysql_conf"
  echo "relay-log = mysql-relay-bin" >> "$mysql_conf"
  echo "log-bin = mysql-bin" >> "$mysql_conf"
  echo "binlog-format = ROW" >> "$mysql_conf"
  echo "read-only = 1" >> "$mysql_conf"
  echo "super-read-only = 1" >> "$mysql_conf"

  # Add GTID configuration for MySQL 5.6+
  echo "gtid-mode = ON" >> "$mysql_conf"
  echo "enforce-gtid-consistency = ON" >> "$mysql_conf"

  # Restart MySQL to apply configuration
  log "Restarting MySQL with replica configuration..."
  callback "configuring" "Applying replica configuration..."
  safe_exec systemctl restart "$service_name"
  safe_exec systemctl enable "$service_name"

  # Wait for MySQL to be ready
  log "Waiting for MySQL replica to be ready..."
  if ! wait_for_service "$service_name"; then
    log "ERROR: MySQL replica failed to start"
    log "MySQL service status:"
    systemctl status "$service_name" --no-pager || true
    log "Recent MySQL error log entries:"
    tail -50 /var/log/mysql/error.log 2>/dev/null || true
    log "Recent journal entries:"
    journalctl -u "$service_name" -n 50 --no-pager || true
    callback "error" "MySQL replica failed to start - check logs"
    exit 1
  fi

  # Start progress monitoring for replication setup
  local progress_pid=$(start_progress_reporter "MySQL replication setup" "")

  # Configure replication using GTID
  log "Configuring MySQL replication with GTID..."
  callback "configuring" "Connecting to primary for replication..."

  # Test connection to primary first
  log "Testing connection to primary MySQL server..."
  if ! MYSQL_PWD="$replication_password" mysql -h "$primary_host" -u replication -e "SELECT 1" >/dev/null 2>&1; then
    stop_progress_reporter "$progress_pid" "MySQL replication setup" "false"
    log "ERROR: Cannot connect to primary MySQL server at $primary_host"
    log "Checking network connectivity:"
    ping -c 3 "$primary_host" || true
    log "Checking if MySQL port is accessible:"
    nc -zv "$primary_host" 3306 || true
    callback "error" "Cannot connect to primary MySQL server - check network and firewall"
    exit 1
  fi
  log "Successfully connected to primary MySQL server"

  # Use GTID-based replication (MASTER_AUTO_POSITION=1)
  log "Configuring replication parameters..."
  if ! MYSQL_PWD="{{ROOT_PASSWORD}}" mysql -u root -e "
    CHANGE MASTER TO
      MASTER_HOST='$primary_host',
      MASTER_USER='replication',
      MASTER_PASSWORD='$replication_password',
      MASTER_AUTO_POSITION=1;
  " 2>/tmp/mysql_replication_error.log; then
    stop_progress_reporter "$progress_pid" "MySQL replication setup" "false"
    log "ERROR: Failed to configure replication"
    log "MySQL error output:"
    cat /tmp/mysql_replication_error.log || true
    log "Recent MySQL error log entries:"
    tail -20 /var/log/mysql/error.log 2>/dev/null || true
    callback "error" "Failed to configure MySQL replication - check logs"
    rm -f /tmp/mysql_replication_error.log
    exit 1
  fi

  # Start replication
  log "Starting replication..."
  if ! MYSQL_PWD="{{ROOT_PASSWORD}}" mysql -u root -e "START SLAVE;" 2>/tmp/mysql_start_slave_error.log; then
    stop_progress_reporter "$progress_pid" "MySQL replication setup" "false"
    log "ERROR: Failed to start replication"
    log "MySQL error output:"
    cat /tmp/mysql_start_slave_error.log || true
    log "Recent MySQL error log entries:"
    tail -20 /var/log/mysql/error.log 2>/dev/null || true
    callback "error" "Failed to start MySQL replication - check logs"
    rm -f /tmp/mysql_start_slave_error.log
    exit 1
  fi

  # Wait a bit for replication to start
  log "Waiting for replication to initialize..."
  sleep 5

  # Verify replication status
  log "Verifying replication status..."
  local slave_status=$(MYSQL_PWD="{{ROOT_PASSWORD}}" mysql -u root -e "SHOW SLAVE STATUS\G" 2>/dev/null || echo "")

  if [ -n "$slave_status" ]; then
    local io_running=$(echo "$slave_status" | grep "Slave_IO_Running:" | awk '{print $2}')
    local sql_running=$(echo "$slave_status" | grep "Slave_SQL_Running:" | awk '{print $2}')
    local last_io_error=$(echo "$slave_status" | grep "Last_IO_Error:" | cut -d: -f2- | xargs)
    local last_sql_error=$(echo "$slave_status" | grep "Last_SQL_Error:" | cut -d: -f2- | xargs)

    log "Replication status: IO_Running=$io_running, SQL_Running=$sql_running"

    if [ "$io_running" = "Yes" ] && [ "$sql_running" = "Yes" ]; then
      stop_progress_reporter "$progress_pid" "MySQL replication setup" "true"
      log "SUCCESS: Replica is successfully replicating from primary"
      callback "configuring" "Replica is ready and replicating from primary"

      # Check replication lag
      local lag=$(echo "$slave_status" | grep "Seconds_Behind_Master:" | awk '{print $2}')
      log "Replication lag: $lag seconds"

      log "MySQL replica setup completed successfully"
    else
      stop_progress_reporter "$progress_pid" "MySQL replication setup" "false"
      log "ERROR: Replication not running properly"
      log "  IO Thread: $io_running"
      log "  SQL Thread: $sql_running"
      if [ -n "$last_io_error" ]; then
        log "  Last IO Error: $last_io_error"
      fi
      if [ -n "$last_sql_error" ]; then
        log "  Last SQL Error: $last_sql_error"
      fi
      log "Full replication status:"
      echo "$slave_status" | while read line; do
        log "  $line"
      done
      log "Recent MySQL error log entries:"
      tail -50 /var/log/mysql/error.log 2>/dev/null || true
      callback "error" "Replica configuration failed - replication not running. Check logs for details."
      exit 1
    fi
  else
    stop_progress_reporter "$progress_pid" "MySQL replication setup" "false"
    log "ERROR: Failed to get replication status"
    log "Recent MySQL error log entries:"
    tail -20 /var/log/mysql/error.log 2>/dev/null || true
    callback "error" "Failed to verify MySQL replication status"
    exit 1
  fi
}