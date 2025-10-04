#!/bin/bash

# DBChest MySQL Cloud Init Script (Modular Version)
# This script sets up a MySQL node using modular components

# Load common functions
source /tmp/common.sh
source /tmp/mysql.sh

# Initialize error handling FIRST
check_root
setup_error_handling

log "========================================="
log "DBChest MySQL Node Setup"
log "========================================="
log "Script started with PID: $$, running as user: $(whoami)"
log "MySQL version: {{DB_VERSION}}"
log "Service name: {{SERVICE_NAME}}"
log "Node type: $([ -n "{{PRIMARY_HOST}}" ] && [ "{{PRIMARY_HOST}}" != "" ] && echo "REPLICA" || echo "PRIMARY")"
log "========================================="

# Step 1: Install essential packages (including curl for callbacks)
install_essential_packages

# Now that curl is installed, send initial callback
callback "configuring" "Starting MySQL installation"

# Step 2: Setup metrics collection early
setup_metrics_collection

# Step 3: Configure SSH access
configure_ssh_access

# Step 4: Install MySQL
set_step "Installing MySQL {{DB_VERSION}}"
install_mysql "{{DB_VERSION}}" "{{SERVICE_NAME}}"

# Step 5: Configure MySQL authentication
set_step "Configuring MySQL authentication"
configure_mysql_auth

# Step 6: Determine if this is a primary or replica setup
if [ -n "{{PRIMARY_HOST}}" ] && [ "{{PRIMARY_HOST}}" != "" ]; then
  # This is a replica node
  # Primary configuration is triggered by CreateService after Terraform completes
  set_step "Configuring as MySQL replica"
  setup_mysql_replica "{{SERVICE_NAME}}"
else
  # This is a primary node
  set_step "Configuring as MySQL primary"
  configure_mysql_primary "{{SERVICE_NAME}}"
fi

# Step 7: Final verification
set_step "Verifying MySQL installation"

log "Checking if MySQL service is active..."
if ! systemctl is-active --quiet "{{SERVICE_NAME}}"; then
  log "ERROR: MySQL service is not running"
  systemctl status "{{SERVICE_NAME}}" --no-pager || true
  journalctl -u "{{SERVICE_NAME}}" -n 50 --no-pager || true
  # This will trigger error handler
  exit 1
fi

log "MySQL service is running - testing database connection..."
# Test database connection
if ! mysql -u root -p"{{ROOT_PASSWORD}}" -e "SELECT VERSION();" >/dev/null 2>&1; then
  log "ERROR: Database connection test failed"
  # This will trigger error handler
  exit 1
fi

log "========================================="
log "SUCCESS: MySQL node setup completed"
log "========================================="
callback "active" "MySQL node is ready and operational"
