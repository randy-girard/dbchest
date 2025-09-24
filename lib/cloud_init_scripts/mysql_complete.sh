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
DEBIAN_FRONTEND=noninteractive apt-get install -y wget gnupg2 lsb-release

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

log "MySQL setup completed successfully"
callback "active" "Database node is ready"
