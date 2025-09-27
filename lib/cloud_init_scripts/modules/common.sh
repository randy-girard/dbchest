#!/bin/bash

# DBChest Cloud Init - Common Functions Module
# This module contains shared functions used across all cloud init scripts

# Ensure we're running as root
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
  fi
}

# Cleanup function
cleanup() {
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    log "Script failed with exit code: $exit_code"
  fi
  log "Cleaning up on exit..."
  rm -f /tmp/dbchest_setup.sh 2>/dev/null || true
  rm -f /tmp/dbchest_wrapper.sh 2>/dev/null || true
  rm -f /tmp/pg_basebackup_output.log 2>/dev/null || true
  log "Cleanup completed"
}

# Set up cleanup trap for various exit scenarios
setup_cleanup_trap() {
  trap cleanup EXIT INT TERM
}

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

# Install essential packages
install_essential_packages() {
  log "Installing essential packages..."
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y curl bc jq wget gnupg2 lsb-release netcat-openbsd
  log "Essential packages installed"
}

# Setup metrics collection system
setup_metrics_collection() {
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
}

# Configure SSH access
configure_ssh_access() {
  log "Configuring SSH access..."
  
  # Set root password for SSH access
  echo "root:{{ROOT_PASSWORD}}" | chpasswd
  log "Root password configured for SSH access"

  # Ensure SSH directory exists
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh

  # SSH key will be handled by Proxmox directly, skipping manual setup
  chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true
  
  log "SSH access configured"
}

# Wait for service to be ready
wait_for_service() {
  local service_name="$1"
  local max_attempts="${2:-30}"
  local wait_interval="${3:-2}"
  
  log "Waiting for $service_name to be ready..."
  
  for i in $(seq 1 $max_attempts); do
    if systemctl is-active --quiet "$service_name"; then
      log "$service_name is active and ready"
      return 0
    fi
    log "Waiting for $service_name to start... ($i/$max_attempts)"
    sleep $wait_interval
  done
  
  log "ERROR: $service_name failed to start within expected time"
  return 1
}

# Enhanced progress reporter for operations with real-time percentage extraction
start_progress_reporter() {
  local operation_name="$1"
  local log_file="$2"
  local check_interval="${3:-3}"  # Default 3 seconds

  {
    local elapsed=0
    local last_percent=""
    local check_count=0

    while true; do
      sleep $check_interval
      elapsed=$((elapsed + check_interval))
      check_count=$((check_count + 1))

      # Look for percentage in log file if provided
      if [ -n "$log_file" ] && [ -f "$log_file" ]; then
        local current_percent=$(grep -o '[0-9]*%' "$log_file" 2>/dev/null | tail -1)

        if [ -n "$current_percent" ] && [ "$current_percent" != "$last_percent" ]; then
          log "$operation_name progress: $current_percent"
          callback "configuring" "$operation_name progress: $current_percent complete"
          last_percent="$current_percent"
        fi
      fi

      # Fallback time-based messages if no percentage found
      if [ -z "$current_percent" ]; then
        if [ $elapsed -eq 9 ]; then
          callback "configuring" "$operation_name started - initializing..."
        elif [ $((elapsed % 30)) -eq 0 ]; then
          local minutes=$((elapsed / 60))
          if [ $minutes -gt 0 ]; then
            callback "configuring" "$operation_name running for ${minutes} minute(s) - please wait..."
          fi
        fi
      fi
    done
  } &

  echo $!  # Return the PID of the background process
}

# Specialized pg_basebackup progress monitor
monitor_pg_basebackup_progress() {
  local backup_log="$1"
  local backup_pid="$2"

  {
    local last_percent=""
    local check_count=0

    while kill -0 $backup_pid 2>/dev/null; do
      sleep 2  # Check every 2 seconds for responsive updates
      check_count=$((check_count + 1))

      if [ -f "$backup_log" ]; then
        # Extract percentage from pg_basebackup output
        local current_percent=$(grep -o '[0-9]*%' "$backup_log" 2>/dev/null | tail -1)

        if [ -n "$current_percent" ] && [ "$current_percent" != "$last_percent" ]; then
          # Send live update to node status endpoint
          log "Base backup progress: $current_percent"
          callback "configuring" "Base backup progress: $current_percent complete"
          last_percent="$current_percent"
        elif [ $check_count -eq 3 ] && [ -z "$current_percent" ]; then
          # Initial message after 6 seconds
          callback "configuring" "Base backup started - initializing transfer..."
        elif [ $((check_count % 15)) -eq 0 ] && [ -z "$current_percent" ]; then
          # Keep-alive every 30 seconds
          local minutes=$((check_count * 2 / 60))
          if [ $minutes -gt 0 ]; then
            callback "configuring" "Base backup running for ${minutes} minute(s) - transferring data..."
          fi
        fi
      fi
    done
  } &

  echo $!  # Return monitor PID
}

# Stop progress reporter
stop_progress_reporter() {
  local reporter_pid="$1"
  local operation_name="$2"
  local success="${3:-true}"
  
  if [ -n "$reporter_pid" ]; then
    kill "$reporter_pid" 2>/dev/null || true
  fi
  
  if [ "$success" = "true" ]; then
    log "$operation_name completed successfully"
    callback "configuring" "$operation_name completed successfully (100%)"
  else
    log "$operation_name failed"
    callback "error" "$operation_name failed - check node logs for details"
  fi
}
