#!/bin/bash
set -e

# Ensure we're running as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

# Cleanup function
cleanup() {
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    log "Script failed with exit code: $exit_code"
  fi
  log "Cleaning up on exit..."
  rm -f /tmp/dbchest_setup.sh 2>/dev/null || true
  rm -f /tmp/dbchest_wrapper.sh 2>/dev/null || true
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

log "Starting DBChest node setup..."
log "Script started with PID: $$, running as user: $(whoami)"
log "PostgreSQL version: {{DB_VERSION}}"
log "Service name: {{SERVICE_NAME}}"
log "DEBUG: PRIMARY_HOST value: '{{PRIMARY_HOST}}'"
log "DEBUG: REPLICATION_PASSWORD value length: ${#{{REPLICATION_PASSWORD}}}"
log "DEBUG: Node appears to be $([ -n "{{PRIMARY_HOST}}" ] && [ "{{PRIMARY_HOST}}" != "" ] && echo "REPLICA" || echo "PRIMARY")"

# Install essential packages first so callbacks and metrics work from the start
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y curl bc jq

# Setup metrics collection FIRST so we can monitor the installation process
log "Setting up metrics collection early..."
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

# Enable and start the systemd timer for metrics collection
systemctl daemon-reload
systemctl enable dbchest-metrics.timer
systemctl start dbchest-metrics.timer
log "Metrics collection started - monitoring available during installation"

callback "configuring" "Starting node configuration..."

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

# PostgreSQL Database Setup Script
log "Setting up PostgreSQL database..."
callback "installing" "Installing PostgreSQL..."

# Create log directory if it doesn't exist
mkdir -p /var/log
touch /var/log/dbchest-setup.log

# Update package lists
log "Updating package lists..."
if ! apt-get update; then
  log "ERROR: Failed to update package lists"
  callback "error" "Failed to update package lists"
  exit 1
fi

# Install basic dependencies (curl already installed at script start)
log "Installing basic dependencies..."
if ! DEBIAN_FRONTEND=noninteractive apt-get install -y wget gnupg2 lsb-release netcat-openbsd; then
  log "ERROR: Failed to install basic dependencies"
  callback "error" "Failed to install basic dependencies"
  exit 1
fi

# Install PostgreSQL using version-specific install command
log "Installing PostgreSQL version {{DB_VERSION}}..."
callback "configuring" "Installing PostgreSQL {{DB_VERSION}}..."

# Log the install command for debugging
log "Executing install command: {{INSTALL_COMMAND}}"

# Execute the version-specific installation command
if ! ({{INSTALL_COMMAND}}); then
  log "ERROR: PostgreSQL installation failed"
  log "Install command that failed: {{INSTALL_COMMAND}}"
  callback "error" "PostgreSQL installation failed"
  exit 1
fi

log "PostgreSQL installation completed successfully"

# Verify PostgreSQL installation and start service if needed
if ! systemctl is-active --quiet {{SERVICE_NAME}}; then
  log "Starting PostgreSQL service..."
  systemctl start {{SERVICE_NAME}}
  systemctl enable {{SERVICE_NAME}}
fi

# Wait for PostgreSQL to be ready
sleep 5

# Store root password
mkdir -p /var/lib/postgresql
echo "{{ROOT_PASSWORD}}" > /var/lib/postgresql/.dbchest_password
chown postgres:postgres /var/lib/postgresql/.dbchest_password
chmod 600 /var/lib/postgresql/.dbchest_password

# Configure PostgreSQL authentication
log "Configuring PostgreSQL authentication..."

# Set postgres user password
if ! sudo -u postgres psql -c "ALTER USER postgres PASSWORD '{{ROOT_PASSWORD}}';"; then
  log "ERROR: Failed to set postgres user password"
  callback "error" "Failed to set postgres user password"
  exit 1
fi

# Configure pg_hba.conf for authentication (version-aware path)
PG_HBA="/etc/postgresql/{{DB_VERSION}}/main/pg_hba.conf"

# Check if pg_hba.conf exists
if [ ! -f "$PG_HBA" ]; then
  log "ERROR: pg_hba.conf not found at $PG_HBA"
  callback "error" "PostgreSQL configuration file not found"
  exit 1
fi

cp "$PG_HBA" "$PG_HBA.backup"

# Update pg_hba.conf
cat > "$PG_HBA" << 'CONFIG_FILE'
local   all             postgres                                peer
local   all             all                                     md5
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
CONFIG_FILE

# Configure postgresql.conf (version-aware path)
log "Configuring PostgreSQL settings..."
PG_CONF="/etc/postgresql/{{DB_VERSION}}/main/postgresql.conf"

# Check if postgresql.conf exists
if [ ! -f "$PG_CONF" ]; then
  log "ERROR: postgresql.conf not found at $PG_CONF"
  callback "error" "PostgreSQL configuration file not found"
  exit 1
fi

cp "$PG_CONF" "$PG_CONF.backup"

# Basic configuration
echo "listen_addresses = '*'" >> "$PG_CONF"
echo "port = 5432" >> "$PG_CONF"
echo "max_connections = 100" >> "$PG_CONF"
echo "shared_buffers = 128MB" >> "$PG_CONF"
echo "logging_collector = on" >> "$PG_CONF"
echo "log_directory = 'log'" >> "$PG_CONF"
echo "log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'" >> "$PG_CONF"
echo "log_statement = 'all'" >> "$PG_CONF"

# Restart PostgreSQL to apply configuration
log "Restarting PostgreSQL to apply configuration..."
if ! systemctl restart {{SERVICE_NAME}}; then
  log "ERROR: Failed to restart PostgreSQL service"
  callback "error" "Failed to restart PostgreSQL service"
  exit 1
fi

systemctl enable {{SERVICE_NAME}}

# Verify PostgreSQL is running
if ! systemctl is-active --quiet {{SERVICE_NAME}}; then
  log "ERROR: PostgreSQL service is not running after restart"
  callback "error" "PostgreSQL service failed to start"
  exit 1
fi

# Test database connectivity
if ! sudo -u postgres psql -c "SELECT version();" > /dev/null 2>&1; then
  log "ERROR: Cannot connect to PostgreSQL database"
  callback "error" "Database connectivity test failed"
  exit 1
fi

# Check if this is a replica setup
PRIMARY_HOST_VAR="{{PRIMARY_HOST}}"
REPLICATION_PASSWORD_VAR="{{REPLICATION_PASSWORD}}"

log "DEBUG: Checking replica variables..."
log "DEBUG: PRIMARY_HOST_VAR='$PRIMARY_HOST_VAR'"
log "DEBUG: REPLICATION_PASSWORD_VAR length: ${#REPLICATION_PASSWORD_VAR}"

if [ -n "$PRIMARY_HOST_VAR" ] && [ "$PRIMARY_HOST_VAR" != "" ]; then
  log "Configuring as PostgreSQL replica..."
  callback "configuring" "Setting up PostgreSQL streaming replication..."
  
  # Get replica configuration variables
  PRIMARY_HOST="$PRIMARY_HOST_VAR"
  REPLICATION_PASSWORD="$REPLICATION_PASSWORD_VAR"
  DB_VERSION="{{DB_VERSION}}"
  
  if [ -z "$PRIMARY_HOST" ] || [ -z "$REPLICATION_PASSWORD" ]; then
    log "ERROR: Missing primary host or replication password for replica setup"
    callback "error" "Replica configuration incomplete - missing primary connection details"
    exit 1
  fi
  
  log "Primary host: $PRIMARY_HOST"
  log "Setting up replica from primary: $PRIMARY_HOST"
  
  # Stop PostgreSQL for replica configuration
  log "Stopping PostgreSQL for replica configuration..."
  callback "configuring" "Preparing for replica setup..."
  systemctl stop {{SERVICE_NAME}}
  
  # Backup existing data directory
  log "Backing up existing data directory..."
  mv "/var/lib/postgresql/$DB_VERSION/main" "/var/lib/postgresql/$DB_VERSION/main.backup.$(date +%s)" 2>/dev/null || true
  
  # Create new data directory
  mkdir -p "/var/lib/postgresql/$DB_VERSION/main"
  chown postgres:postgres "/var/lib/postgresql/$DB_VERSION/main"
  chmod 700 "/var/lib/postgresql/$DB_VERSION/main"
  
  # Take base backup from primary
  log "Taking base backup from primary..."
  callback "configuring" "Preparing to download base backup from primary ($PRIMARY_HOST)..."
  
  # Set timeout for base backup (30 minutes)
  BACKUP_TIMEOUT=1800
  
  # Wait for primary to be available
  log "Checking primary availability..."
  for i in {1..30}; do
    if nc -z "$PRIMARY_HOST" 5432 2>/dev/null; then
      log "Primary is available"
      break
    fi
    log "Waiting for primary to be available... ($i/30)"
    sleep 10
  done
  
  if ! nc -z "$PRIMARY_HOST" 5432 2>/dev/null; then
    log "ERROR: Primary host $PRIMARY_HOST is not reachable on port 5432"
    callback "error" "Primary host not reachable for replication"
    exit 1
  fi
  
  # Create .pgpass file for replication user authentication
  log "Setting up authentication for base backup..."
  callback "configuring" "Setting up replication authentication..."
  PGPASS_FILE="/var/lib/postgresql/.pgpass"
  echo "$PRIMARY_HOST:5432:*:replication:$REPLICATION_PASSWORD" > "$PGPASS_FILE"
  chown postgres:postgres "$PGPASS_FILE"
  chmod 600 "$PGPASS_FILE"
  
  # Test authentication before starting backup
  log "Testing replication connection to primary..."
  callback "configuring" "Verifying replication user credentials..."
  if ! sudo -u postgres psql -h "$PRIMARY_HOST" -U replication -d postgres -c "SELECT 1;" > /dev/null 2>&1; then
    log "ERROR: Cannot authenticate as replication user to primary"
    callback "error" "Replication authentication failed - check if primary is configured"
    rm -f "$PGPASS_FILE"
    exit 1
  fi
  log "Replication authentication successful"
  
  # Take the base backup with progress monitoring
  log "Executing pg_basebackup from primary..."
  callback "configuring" "Starting base backup from primary..."
  
  # Simple timer-based progress reporting
  log "Starting base backup with simple progress reporting..."

  # Start simple progress reporter in background
  {
    local elapsed=0
    local interval=10  # Update every 10 seconds

    while true; do
      sleep $interval
      elapsed=$((elapsed + interval))

      # Send periodic updates
      if [ $elapsed -eq 10 ]; then
        callback "configuring" "Base backup started - downloading database files..."
        log "Base backup progress: started"
      elif [ $elapsed -eq 30 ]; then
        callback "configuring" "Base backup in progress - copying data files..."
        log "Base backup progress: copying data"
      elif [ $elapsed -eq 60 ]; then
        callback "configuring" "Base backup continuing - this may take several minutes..."
        log "Base backup progress: continuing"
      elif [ $((elapsed % 60)) -eq 0 ]; then
        local minutes=$((elapsed / 60))
        callback "configuring" "Base backup running for ${minutes} minute(s) - please wait..."
        log "Base backup progress: ${minutes} minutes elapsed"
      fi
    done
  } &
  PROGRESS_PID=$!

  # Run pg_basebackup
  log "Executing pg_basebackup..."
  if timeout $BACKUP_TIMEOUT sudo -u postgres PGPASSWORD="$REPLICATION_PASSWORD" pg_basebackup \
    -h "$PRIMARY_HOST" \
    -D "/var/lib/postgresql/$DB_VERSION/main" \
    -U replication \
    -v \
    -P \
    -R \
    -W; then

    # Stop progress reporter
    kill $PROGRESS_PID 2>/dev/null || true

    log "Base backup completed successfully"
    callback "configuring" "Base backup completed successfully"
  else
    # Stop progress reporter
    kill $PROGRESS_PID 2>/dev/null || true

    BACKUP_EXIT_CODE=$?
    log "ERROR: pg_basebackup failed with exit code $BACKUP_EXIT_CODE"
    callback "error" "Base backup failed - check node logs for details"
    exit 1
  fi
  
  # Ensure proper configuration for replica
  log "Configuring replica settings..."
  callback "configuring" "Setting up replica configuration..."
  
  # Set proper ownership and permissions
  chown -R postgres:postgres "/var/lib/postgresql/$DB_VERSION/main"
  chmod 700 "/var/lib/postgresql/$DB_VERSION/main"
  
  # Add replica-specific configuration to postgresql.conf if needed
  PG_CONF="/etc/postgresql/$DB_VERSION/main/postgresql.conf"
  if ! grep -q "hot_standby = on" "$PG_CONF"; then
    echo "hot_standby = on" >> "$PG_CONF"
  fi
  
  # Verify primary_conninfo was created by pg_basebackup -R
  if [ -f "/var/lib/postgresql/$DB_VERSION/main/postgresql.auto.conf" ]; then
    log "Replica configuration found in postgresql.auto.conf"
  else
    log "WARNING: postgresql.auto.conf not found, creating primary connection info"
    CONFIG_FILE="/var/lib/postgresql/$DB_VERSION/main/postgresql.auto.conf"
    echo "primary_conninfo = 'host=$PRIMARY_HOST port=5432 user=replication password=$REPLICATION_PASSWORD application_name=$(hostname)'" > "$CONFIG_FILE"
    chown postgres:postgres "$CONFIG_FILE"
  fi
  
  # Start PostgreSQL as replica
  log "Starting PostgreSQL replica..."
  callback "configuring" "Starting PostgreSQL replica..."
  systemctl start {{SERVICE_NAME}}
  systemctl enable {{SERVICE_NAME}}
  
  # Wait for PostgreSQL to start up completely
  log "Waiting for PostgreSQL replica to start up..."
  for i in {1..30}; do
    if systemctl is-active --quiet {{SERVICE_NAME}}; then
      log "PostgreSQL service is active"
      break
    fi
    log "Waiting for PostgreSQL to start... ($i/30)"
    sleep 2
  done
  
  # Verify replica is in recovery mode
  log "Verifying replication status..."
  callback "configuring" "Checking if replica is in recovery mode..."
  
  # Wait a bit more for the replica to enter recovery mode
  sleep 5
  
  if sudo -u postgres psql -t -c "SELECT pg_is_in_recovery();" 2>/dev/null | grep -q "t"; then
    log "Replica is successfully in recovery mode"
    callback "configuring" "Replica is in recovery mode - checking replication lag..."
    
    # Check replication lag
    LAG_RESULT=$(sudo -u postgres psql -t -c "SELECT CASE WHEN pg_is_in_recovery() THEN EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::int ELSE 0 END AS lag_seconds;" 2>/dev/null || echo "unknown")
    log "Current replication lag: $LAG_RESULT seconds"
    
    log "PostgreSQL replica setup completed successfully"
    callback "active" "Replica is ready and replicating from primary"
  else
    log "ERROR: Replica is not in recovery mode"
    callback "error" "Replica configuration failed - not in recovery mode"
    
    # Show some debugging info
    log "Debug: Checking PostgreSQL status..."
    sudo -u postgres psql -c "SELECT pg_is_in_recovery();" 2>&1 | head -10
    exit 1
  fi
  
  # Clean up .pgpass file for security
  rm -f "$PGPASS_FILE"
  
else
  log "Configuring as PostgreSQL primary..."
  callback "configuring" "Primary setup completed"
  
  # For primary nodes, ensure replication configuration is in place
  PG_CONF="/etc/postgresql/{{DB_VERSION}}/main/postgresql.conf"
  
  # Enable WAL archiving and replication settings for primary
  if ! grep -q "wal_level = replica" "$PG_CONF"; then
    echo "wal_level = replica" >> "$PG_CONF"
  fi
  if ! grep -q "max_wal_senders = 3" "$PG_CONF"; then
    echo "max_wal_senders = 3" >> "$PG_CONF"
  fi
  if ! grep -q "max_replication_slots = 3" "$PG_CONF"; then
    echo "max_replication_slots = 3" >> "$PG_CONF"
  fi
  
  # Restart PostgreSQL to apply replication settings
  log "Restarting PostgreSQL to apply replication configuration..."
  systemctl restart {{SERVICE_NAME}}
  
  # Wait for restart
  sleep 5
  
  # Verify it's still working
  if ! systemctl is-active --quiet {{SERVICE_NAME}}; then
    log "ERROR: PostgreSQL failed to restart with replication configuration"
    callback "error" "PostgreSQL failed to restart with replication settings"
    exit 1
  fi
  
  log "PostgreSQL primary setup completed successfully"
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

# Metrics collection was already set up at the beginning of the script

log "PostgreSQL setup completed successfully"
callback "active" "Database node is ready"
