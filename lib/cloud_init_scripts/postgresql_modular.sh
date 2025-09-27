#!/bin/bash
set -e

# DBChest PostgreSQL Cloud Init Script (Modular Version)
# This script sets up a PostgreSQL node using modular components

# Load common functions
source /tmp/common.sh
source /tmp/postgresql.sh

# Initialize
check_root
setup_cleanup_trap

log "Starting DBChest PostgreSQL node setup..."
log "Script started with PID: $$, running as user: $(whoami)"
log "PostgreSQL version: {{DB_VERSION}}"
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

# Step 4: Install PostgreSQL
install_postgresql "{{DB_VERSION}}" "{{SERVICE_NAME}}"

# Step 5: Configure PostgreSQL authentication
configure_postgresql_auth

# Step 6: Determine if this is a primary or replica setup
if [ -n "{{PRIMARY_HOST}}" ] && [ "{{PRIMARY_HOST}}" != "" ]; then
  # This is a replica node
  log "Setting up as PostgreSQL replica"
  callback "configuring" "Configuring as PostgreSQL replica..."
  
  setup_postgresql_replica "{{DB_VERSION}}" "{{SERVICE_NAME}}"
  
  # Notify primary to configure for this replica
  callback "configure_primary_for_replica" "Configure primary for replica at $(hostname -I | awk '{print $1}')"
else
  # This is a primary node
  log "Setting up as PostgreSQL primary"
  callback "configuring" "Configuring as PostgreSQL primary..."
  
  configure_postgresql_primary "{{DB_VERSION}}" "{{SERVICE_NAME}}"
fi

# Step 7: Final verification
log "Verifying PostgreSQL installation..."
callback "configuring" "Verifying PostgreSQL installation..."

if systemctl is-active --quiet "{{SERVICE_NAME}}"; then
  log "SUCCESS: PostgreSQL is running and active"
  
  # Test database connection (using su to avoid sudo issues)
  if su - postgres -c "psql -c 'SELECT version();'" >/dev/null 2>&1; then
    log "SUCCESS: Database connection test passed"
    callback "active" "PostgreSQL node is ready and operational"
  else
    log "WARNING: Database connection test failed"
    callback "error" "PostgreSQL installed but connection test failed"
    exit 1
  fi
else
  log "ERROR: PostgreSQL service is not running"
  callback "error" "PostgreSQL service failed to start"
  exit 1
fi

log "PostgreSQL node setup completed successfully"
