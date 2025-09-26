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
  local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$message" | tee -a /var/log/dbchest-setup.log
}

# Callback function to update node status
callback() {
  local status="$1"
  local message="$2"
  
  curl -s -X POST "{{CALLBACK_URL}}" \
    -H "Content-Type: application/json" \
    -d "{\"status\": \"$status\", \"message\": \"$message\"}" || true
}

log "Starting DBChest MySQL node setup..."

# Install curl first so callbacks work from the start
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y curl

callback "configuring" "Starting MySQL node configuration..."

# Set root password for SSH access
echo "root:{{ROOT_PASSWORD}}" | chpasswd
log "Root password configured for SSH access"

# Ensure SSH directory exists
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# SSH key will be handled by Proxmox directly, skipping manual setup
chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true

# Configure SSH to allow password authentication
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Ensure SSH service is running
systemctl enable ssh
systemctl restart ssh

log "SSH configuration completed with password authentication enabled"

# MySQL Database Setup Script
log "Setting up MySQL database..."
callback "installing" "Installing MySQL..."

# Update package lists
apt-get update

# Install basic dependencies (curl already installed at script start)
DEBIAN_FRONTEND=noninteractive apt-get install -y wget gnupg2 lsb-release netcat-openbsd

# Install MySQL using version-specific install command
log "Installing MySQL version {{DB_VERSION}}..."
callback "configuring" "Installing MySQL {{DB_VERSION}}..."

# Execute the version-specific installation command
{{INSTALL_COMMAND}}

# Store root password
echo "{{ROOT_PASSWORD}}" > /var/lib/mysql/.dbchest_password
chown mysql:mysql /var/lib/mysql/.dbchest_password
chmod 600 /var/lib/mysql/.dbchest_password

# Configure MySQL authentication
log "Configuring MySQL authentication..."

# Set root password
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '{{ROOT_PASSWORD}}';"

# Configure MySQL for remote connections
MYSQL_CONF="/etc/mysql/mysql.conf.d/mysqld.cnf"
cp "$MYSQL_CONF" "$MYSQL_CONF.backup"

# Basic configuration
sed -i 's/bind-address.*/bind-address = 0.0.0.0/' "$MYSQL_CONF"
echo "max_connections = 100" >> "$MYSQL_CONF"
echo "general_log = 1" >> "$MYSQL_CONF"
echo "general_log_file = /var/log/mysql/mysql.log" >> "$MYSQL_CONF"

# Restart MySQL to apply configuration
systemctl restart {{SERVICE_NAME}}
systemctl enable {{SERVICE_NAME}}

# Verify MySQL is running
systemctl is-active {{SERVICE_NAME}}

# Check if this is a replica setup
if [ -n "{{PRIMARY_HOST}}" ] && [ "{{PRIMARY_HOST}}" != "" ]; then
  log "Configuring as MySQL replica..."
  callback "configuring" "Setting up MySQL replication..."
  
  # Get replica configuration variables
  PRIMARY_HOST="{{PRIMARY_HOST}}"
  REPLICATION_PASSWORD="{{REPLICATION_PASSWORD}}"
  
  if [ -z "$PRIMARY_HOST" ] || [ -z "$REPLICATION_PASSWORD" ]; then
    log "ERROR: Missing primary host or replication password for replica setup"
    callback "error" "Replica configuration incomplete - missing primary connection details"
    exit 1
  fi
  
  log "Primary host: $PRIMARY_HOST"
  log "Setting up replica from primary: $PRIMARY_HOST"
  
  # Wait for primary to be available
  log "Checking primary availability..."
  for i in {1..30}; do
    if nc -z "$PRIMARY_HOST" 3306 2>/dev/null; then
      log "Primary is available"
      break
    fi
    log "Waiting for primary to be available... ($i/30)"
    sleep 10
  done
  
  if ! nc -z "$PRIMARY_HOST" 3306 2>/dev/null; then
    log "ERROR: Primary host $PRIMARY_HOST is not reachable on port 3306"
    callback "error" "Primary host not reachable for replication"
    exit 1
  fi
  
  # Configure MySQL replica settings
  log "Configuring MySQL replica settings..."
  callback "configuring" "Setting up MySQL replication configuration..."
  
  # Add replication settings to MySQL configuration
  echo "server-id = $(hostname | md5sum | head -c8 | perl -pe 's/[a-f]/1/g' | head -c8)" >> "$MYSQL_CONF"
  echo "relay-log = /var/log/mysql/mysql-relay-bin.log" >> "$MYSQL_CONF"
  echo "log-bin = /var/log/mysql/mysql-bin.log" >> "$MYSQL_CONF"
  echo "binlog-format = ROW" >> "$MYSQL_CONF"
  
  # Restart MySQL to apply replication configuration
  log "Restarting MySQL with replication configuration..."
  systemctl restart {{SERVICE_NAME}}
  
  # Wait for MySQL to start
  sleep 10
  
  if ! systemctl is-active --quiet {{SERVICE_NAME}}; then
    log "ERROR: MySQL failed to restart with replication configuration"
    callback "error" "MySQL failed to restart with replication settings"
    exit 1
  fi
  
  # Set up replication
  log "Setting up MySQL replication connection..."
  callback "configuring" "Connecting to primary for replication..."
  
  mysql -e "
    CHANGE MASTER TO
      MASTER_HOST='$PRIMARY_HOST',
      MASTER_USER='replication',
      MASTER_PASSWORD='$REPLICATION_PASSWORD',
      MASTER_AUTO_POSITION=1;
    START SLAVE;
  "
  
  # Check replication status
  log "Checking replication status..."
  sleep 5
  
  SLAVE_STATUS=$(mysql -e "SHOW SLAVE STATUS\G" | grep "Slave_IO_Running\|Slave_SQL_Running\|Last_Error")
  log "Replication status: $SLAVE_STATUS"
  
  IO_RUNNING=$(mysql -e "SHOW SLAVE STATUS\G" | grep "Slave_IO_Running:" | awk '{print $2}')
  SQL_RUNNING=$(mysql -e "SHOW SLAVE STATUS\G" | grep "Slave_SQL_Running:" | awk '{print $2}')
  
  if [ "$IO_RUNNING" = "Yes" ] && [ "$SQL_RUNNING" = "Yes" ]; then
    log "MySQL replica setup completed successfully"
    callback "active" "Replica is ready and replicating from primary"
  else
    log "ERROR: MySQL replication failed to start properly"
    log "IO Running: $IO_RUNNING, SQL Running: $SQL_RUNNING"
    callback "error" "MySQL replication failed to start"
    exit 1
  fi
else
  log "Configuring as MySQL primary..."
  callback "configuring" "Primary setup completed"
  
  # For primary nodes, ensure replication configuration is in place
  # Add binary logging and server-id for replication capability
  if ! grep -q "log-bin" "$MYSQL_CONF"; then
    echo "log-bin = /var/log/mysql/mysql-bin.log" >> "$MYSQL_CONF"
  fi
  if ! grep -q "server-id" "$MYSQL_CONF"; then
    echo "server-id = 1" >> "$MYSQL_CONF"
  fi
  if ! grep -q "binlog-format" "$MYSQL_CONF"; then
    echo "binlog-format = ROW" >> "$MYSQL_CONF"
  fi
  
  # Restart MySQL to apply replication settings
  log "Restarting MySQL to apply replication configuration..."
  systemctl restart {{SERVICE_NAME}}
  
  # Wait for restart
  sleep 5
  
  # Verify it's still working
  if ! systemctl is-active --quiet {{SERVICE_NAME}}; then
    log "ERROR: MySQL failed to restart with replication configuration"
    callback "error" "MySQL failed to restart with replication settings"
    exit 1
  fi
  
  log "MySQL primary setup completed successfully"
fi

# Setup metrics collection
setup_metrics_collection() {
  log "Setting up metrics collection..."
  callback "configuring" "Installing metrics collection system..."

  # Create metrics collector script
  cat > /usr/local/bin/dbchest-metrics-collector.sh << 'METRICS_SCRIPT_EOF'
{{METRICS_COLLECTOR_SCRIPT}}
METRICS_SCRIPT_EOF

  # Make script executable
  chmod +x /usr/local/bin/dbchest-metrics-collector.sh

  # Create systemd service
  cat > /etc/systemd/system/dbchest-metrics.service << 'SERVICE_EOF'
{{METRICS_SERVICE}}
SERVICE_EOF

  # Create systemd timer
  cat > /etc/systemd/system/dbchest-metrics.timer << 'TIMER_EOF'
{{METRICS_TIMER}}
TIMER_EOF

  # Reload systemd and enable the timer
  systemctl daemon-reload
  systemctl enable dbchest-metrics.timer
  systemctl start dbchest-metrics.timer

  log "Metrics collection service installed and started"
  callback "configuring" "Metrics collection system active"
}

# Call metrics setup function
setup_metrics_collection

log "MySQL setup completed successfully"
callback "active" "Database node is ready"
