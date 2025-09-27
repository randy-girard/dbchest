#!/bin/bash

# DBChest Cloud Init - MySQL Module
# This module contains MySQL-specific installation and configuration functions

# Install MySQL
install_mysql() {
  local db_version="$1"
  local service_name="$2"
  
  log "Installing MySQL version $db_version..."
  callback "configuring" "Installing MySQL $db_version..."

  # Execute the version-specific installation command
  {{INSTALL_COMMAND}}

  # Store root password
  echo "{{ROOT_PASSWORD}}" > /var/lib/mysql/.dbchest_password
  chown mysql:mysql /var/lib/mysql/.dbchest_password
  chmod 600 /var/lib/mysql/.dbchest_password

  log "MySQL $db_version installed successfully"
}

# Configure MySQL authentication
configure_mysql_auth() {
  log "Configuring MySQL authentication..."

  # Set root password
  mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '{{ROOT_PASSWORD}}';"

  log "MySQL authentication configured"
}

# Configure MySQL for replication (primary)
configure_mysql_primary() {
  local service_name="$1"
  
  log "Configuring MySQL as primary for replication..."
  callback "configuring" "Setting up MySQL replication (primary)..."

  # Configure MySQL for remote connections
  local mysql_conf="/etc/mysql/mysql.conf.d/mysqld.cnf"
  cp "$mysql_conf" "$mysql_conf.backup"

  # Basic configuration
  sed -i 's/bind-address.*/bind-address = 0.0.0.0/' "$mysql_conf"
  echo "max_connections = 100" >> "$mysql_conf"
  echo "general_log = 1" >> "$mysql_conf"
  echo "general_log_file = /var/log/mysql/mysql.log" >> "$mysql_conf"

  # Replication configuration
  echo "server-id = 1" >> "$mysql_conf"
  echo "log-bin = mysql-bin" >> "$mysql_conf"
  echo "binlog-format = ROW" >> "$mysql_conf"

  # Restart MySQL to apply configuration
  systemctl restart "$service_name"
  systemctl enable "$service_name"

  # Wait for MySQL to be ready
  if ! wait_for_service "$service_name"; then
    log "ERROR: MySQL failed to start after configuration"
    callback "error" "MySQL failed to start after configuration"
    exit 1
  fi

  # Create replication user
  mysql -u root -p"{{ROOT_PASSWORD}}" -e "CREATE USER 'replication'@'%' IDENTIFIED BY '{{REPLICATION_PASSWORD}}';" || true
  mysql -u root -p"{{ROOT_PASSWORD}}" -e "GRANT REPLICATION SLAVE ON *.* TO 'replication'@'%';" || true
  mysql -u root -p"{{ROOT_PASSWORD}}" -e "FLUSH PRIVILEGES;" || true

  log "MySQL primary configuration completed"
}

# Setup MySQL replica
setup_mysql_replica() {
  local service_name="$1"
  local primary_host="{{PRIMARY_HOST}}"
  local replication_password="{{REPLICATION_PASSWORD}}"
  
  log "Setting up MySQL replica from primary: $primary_host"
  callback "configuring" "Setting up MySQL replica..."

  # Configure MySQL for replication
  local mysql_conf="/etc/mysql/mysql.conf.d/mysqld.cnf"
  cp "$mysql_conf" "$mysql_conf.backup"

  # Basic configuration
  sed -i 's/bind-address.*/bind-address = 0.0.0.0/' "$mysql_conf"
  echo "max_connections = 100" >> "$mysql_conf"
  echo "general_log = 1" >> "$mysql_conf"
  echo "general_log_file = /var/log/mysql/mysql.log" >> "$mysql_conf"

  # Replica configuration
  echo "server-id = 2" >> "$mysql_conf"
  echo "relay-log = mysql-relay-bin" >> "$mysql_conf"
  echo "log-bin = mysql-bin" >> "$mysql_conf"
  echo "binlog-format = ROW" >> "$mysql_conf"
  echo "read-only = 1" >> "$mysql_conf"

  # Restart MySQL to apply configuration
  systemctl restart "$service_name"
  systemctl enable "$service_name"

  # Wait for MySQL to be ready
  if ! wait_for_service "$service_name"; then
    log "ERROR: MySQL replica failed to start"
    callback "error" "MySQL replica failed to start"
    exit 1
  fi

  # Start progress monitoring for replication setup
  local progress_pid=$(start_progress_reporter "MySQL replication setup" "")

  # Configure replication
  log "Configuring MySQL replication..."
  
  # Get master status from primary
  local master_status=$(mysql -h "$primary_host" -u replication -p"$replication_password" -e "SHOW MASTER STATUS\G" 2>/dev/null || echo "")
  
  if [ -n "$master_status" ]; then
    local log_file=$(echo "$master_status" | grep "File:" | awk '{print $2}')
    local log_pos=$(echo "$master_status" | grep "Position:" | awk '{print $2}')
    
    # Configure replica
    mysql -u root -p"{{ROOT_PASSWORD}}" -e "
      CHANGE MASTER TO 
        MASTER_HOST='$primary_host',
        MASTER_USER='replication',
        MASTER_PASSWORD='$replication_password',
        MASTER_LOG_FILE='$log_file',
        MASTER_LOG_POS=$log_pos;
    " || true
    
    # Start replication
    mysql -u root -p"{{ROOT_PASSWORD}}" -e "START SLAVE;" || true
    
    stop_progress_reporter "$progress_pid" "MySQL replication setup" "true"
    log "MySQL replica setup completed"
  else
    stop_progress_reporter "$progress_pid" "MySQL replication setup" "false"
    log "ERROR: Failed to get master status from primary"
    callback "error" "Failed to connect to MySQL primary for replication setup"
    exit 1
  fi
}