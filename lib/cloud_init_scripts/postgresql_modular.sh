#!/bin/bash

# DBChest PostgreSQL Cloud Init Script (Modular Version)
# This script sets up a PostgreSQL node using modular components

# Load common functions
source /tmp/common.sh
source /tmp/version_compatibility.sh
source /tmp/postgresql.sh

# Initialize error handling FIRST
check_root
setup_error_handling

log "========================================="
log "DBChest PostgreSQL Node Setup"
log "========================================="
log "Script started with PID: $$, running as user: $(whoami)"
log "PostgreSQL version: {{DB_VERSION}}"
log "Service name: {{SERVICE_NAME}}"
log "Node type: $([ -n "{{PRIMARY_HOST}}" ] && [ "{{PRIMARY_HOST}}" != "" ] && echo "REPLICA" || echo "PRIMARY")"
log "========================================="

# Display version compatibility information
display_compatibility_matrix

# Step 1: Install essential packages (including curl for callbacks)
install_essential_packages

# Now that curl is installed, send initial callback
callback "configuring" "Starting PostgreSQL installation"

# Step 2: Setup metrics collection early
setup_metrics_collection

# Step 3: Configure SSH access
configure_ssh_access

# Step 4: Install PostgreSQL
set_step "Installing PostgreSQL {{DB_VERSION}}"
install_postgresql "{{DB_VERSION}}" "{{SERVICE_NAME}}"

# Step 5: Configure PostgreSQL authentication
set_step "Configuring PostgreSQL authentication"
configure_postgresql_auth

# Step 6: Determine if this is a primary or replica setup
if [ -n "{{PRIMARY_HOST}}" ] && [ "{{PRIMARY_HOST}}" != "" ]; then
  # This is a replica node
  set_step "Waiting for primary configuration"

  # Primary configuration is triggered by CreateService after Terraform completes
  # We just need to wait for the replication user to be created
  log "Waiting for primary to be configured for replication..."
  callback "configuring" "Waiting for primary to configure replication access..."

  # Wait up to 5 minutes for primary configuration
  max_wait=300  # 5 minutes
  wait_interval=10
  waited=0

  while [ $waited -lt $max_wait ]; do
    log "Waiting for primary configuration... ($waited/$max_wait seconds)"
    sleep $wait_interval
    waited=$((waited + wait_interval))

    # Try to test connection to primary (this will fail until replication user is created)
    if PGPASSWORD="{{REPLICATION_PASSWORD}}" psql -h "{{PRIMARY_HOST}}" -U replication -d postgres -c "SELECT 1" >/dev/null 2>&1; then
      log "Primary is configured and replication user is accessible"
      break
    fi
  done

  if [ $waited -ge $max_wait ]; then
    log "WARNING: Timed out waiting for primary configuration, proceeding anyway..."
    callback "configuring" "Primary configuration timeout - attempting base backup..."
  else
    log "Primary configuration confirmed after $waited seconds"
    callback "configuring" "Primary configured - starting base backup..."
  fi

  # Now proceed with replica setup
  set_step "Configuring as PostgreSQL replica"
  setup_postgresql_replica "{{DB_VERSION}}" "{{SERVICE_NAME}}"
else
  # This is a primary node
  set_step "Configuring as PostgreSQL primary"
  configure_postgresql_primary "{{DB_VERSION}}" "{{SERVICE_NAME}}"
fi

# Step 7: Final verification
set_step "Verifying PostgreSQL installation"

log "Checking if PostgreSQL service is active..."
if ! systemctl is-active --quiet "{{SERVICE_NAME}}"; then
  log "ERROR: PostgreSQL service is not running"
  systemctl status "{{SERVICE_NAME}}" --no-pager || true
  journalctl -u "{{SERVICE_NAME}}" -n 50 --no-pager || true
  # This will trigger error handler
  exit 1
fi

log "PostgreSQL service is running - testing database connection..."
# Test database connection (using su to avoid sudo issues)
if ! su - postgres -c "psql -c 'SELECT version();'" >/dev/null 2>&1; then
  log "ERROR: Database connection test failed"
  # This will trigger error handler
  exit 1
fi

log "========================================="
log "SUCCESS: PostgreSQL node setup completed"
log "========================================="
callback "active" "PostgreSQL node is ready and operational"
