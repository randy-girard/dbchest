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

log "Starting DBChest node setup..."
callback "configuring" "Starting node configuration..."

# Ensure SSH directory exists
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# SSH key will be handled by Proxmox directly, skipping manual setup
chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true

# Ensure SSH service is running
systemctl enable ssh
systemctl start ssh || systemctl restart ssh

log "SSH key setup completed"
