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
  echo "[$$(date '+%Y-%m-%d %H:%M:%S')] $$1" | tee -a /var/log/dbchest-setup.log
}

# Callback function to update node status
callback() {
  local status="$$1"
  local message="$$2"
  
  curl -s -X POST "{{CALLBACK_URL}}" \
    -H "Content-Type: application/json" \
    -d "{\"status\": \"$$status\", \"message\": \"$$message\"}" || true
}

log "Starting DBChest node setup..."
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

# Update package lists
apt-get update

# Install PostgreSQL using version-specific install command
log "Installing PostgreSQL version {{DB_VERSION}}..."
callback "configuring" "Installing PostgreSQL {{DB_VERSION}}..."

# Execute the version-specific installation command
{{INSTALL_COMMAND}}

# Store root password
echo "{{ROOT_PASSWORD}}" > /var/lib/postgresql/.dbchest_password

# Configure PostgreSQL authentication
log "Configuring PostgreSQL authentication..."

# Set postgres user password
sudo -u postgres psql -c "ALTER USER postgres PASSWORD '{{ROOT_PASSWORD}}';"

# Configure pg_hba.conf for authentication (version-aware path)
PG_HBA="/etc/postgresql/{{DB_VERSION}}/main/pg_hba.conf"
cp "$$PG_HBA" "$$PG_HBA.backup"

# Update pg_hba.conf
cat > "$$PG_HBA" << 'CONFIG_FILE'
local   all             postgres                                peer
local   all             all                                     md5
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
CONFIG_FILE

# Configure postgresql.conf (version-aware path)
log "Configuring PostgreSQL settings..."
PG_CONF="/etc/postgresql/{{DB_VERSION}}/main/postgresql.conf"
cp "$$PG_CONF" "$$PG_CONF.backup"

# Basic configuration
echo "listen_addresses = '*'" >> "$$PG_CONF"
echo "port = 5432" >> "$$PG_CONF"
echo "max_connections = 100" >> "$$PG_CONF"
echo "shared_buffers = 128MB" >> "$$PG_CONF"
echo "logging_collector = on" >> "$$PG_CONF"
echo "log_directory = 'log'" >> "$$PG_CONF"
echo "log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'" >> "$$PG_CONF"
echo "log_statement = 'all'" >> "$$PG_CONF"

# Restart PostgreSQL to apply configuration
systemctl restart {{SERVICE_NAME}}
systemctl enable {{SERVICE_NAME}}

# Verify PostgreSQL is running
systemctl is-active {{SERVICE_NAME}}

log "PostgreSQL setup completed successfully"
callback "active" "Database node is ready"
