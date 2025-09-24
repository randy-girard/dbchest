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

log "PostgreSQL setup completed successfully"
callback "active" "Database node is ready"
