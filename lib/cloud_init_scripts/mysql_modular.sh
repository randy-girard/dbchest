#!/bin/bash
set -e

# DBChest MySQL Cloud Init Script (Modular Version)
# This script sets up a MySQL node using modular components

# Load common functions
source /tmp/common.sh
source /tmp/mysql.sh

# Initialize
check_root
setup_cleanup_trap

log "Starting DBChest MySQL node setup..."
log "Script started with PID: $$, running as user: $(whoami)"
log "MySQL version: {{DB_VERSION}}"
log "Service name: {{SERVICE_NAME}}"
log "DEBUG: PRIMARY_HOST value: '{{PRIMARY_HOST}}'"
log "DEBUG: REPLICATION_PASSWORD value length: ${#{{REPLICATION_PASSWORD}}}"
log "DEBUG: Node appears to be $([ -n "{{PRIMARY_HOST}}" ] && [ "{{PRIMARY_HOST}}" != "" ] && echo "REPLICA" || echo "PRIMARY")"

# Step 1: Install essential packages
install_essential_packages

# Step 2: Setup metrics collection early
setup_metrics_collection

# Step 3: Configure SSH access
configure_ssh_access

# Step 4: Install MySQL
install_mysql "{{DB_VERSION}}" "{{SERVICE_NAME}}"

# Step 5: Configure MySQL authentication
configure_mysql_auth

# Step 6: Determine if this is a primary or replica setup
if [ -n "{{PRIMARY_HOST}}" ] && [ "{{PRIMARY_HOST}}" != "" ]; then
  # This is a replica node
  log "Setting up as MySQL replica"
  callback "configuring" "Configuring as MySQL replica..."
  
  setup_mysql_replica "{{SERVICE_NAME}}"
  
  # Notify primary to configure for this replica
  callback "configure_primary_for_replica" "Configure primary for replica at $(hostname -I | awk '{print $1}')"
else
  # This is a primary node
  log "Setting up as MySQL primary"
  callback "configuring" "Configuring as MySQL primary..."
  
  configure_mysql_primary "{{SERVICE_NAME}}"
fi

# Step 7: Final verification
log "Verifying MySQL installation..."
callback "configuring" "Verifying MySQL installation..."

if systemctl is-active --quiet "{{SERVICE_NAME}}"; then
  log "SUCCESS: MySQL is running and active"
  
  # Test database connection
  if mysql -u root -p"{{ROOT_PASSWORD}}" -e "SELECT VERSION();" >/dev/null 2>&1; then
    log "SUCCESS: Database connection test passed"
    callback "active" "MySQL node is ready and operational"
  else
    log "WARNING: Database connection test failed"
    callback "error" "MySQL installed but connection test failed"
    exit 1
  fi
else
  log "ERROR: MySQL service is not running"
  callback "error" "MySQL service failed to start"
  exit 1
fi

log "MySQL node setup completed successfully"
