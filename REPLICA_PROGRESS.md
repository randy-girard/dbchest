# Enhanced Replica Progress Monitoring

## Overview

The replica creation process now provides detailed real-time progress updates via ActionCable, giving users visibility into each step of the `pg_basebackup` process and replica initialization.

## Enhanced Features

### 1. pg_basebackup Progress Monitoring

The system now parses `pg_basebackup` output in real-time and sends progress updates:

```bash
# Real-time monitoring of pg_basebackup output
sudo -u postgres pg_basebackup -h primary_ip -D /var/lib/postgresql/$PG_VERSION/main -U replication -v -P -W -R 2>&1 | while IFS= read -r line; do
  log "pg_basebackup: $line"
  
  # Parse different types of progress information
  if echo "$line" | grep -qE "[0-9]+/[0-9]+ kB.*transferred"; then
    # Data transfer progress: "12345/67890 kB (18%), 1/1 tablespace"
    callback "configuring" "Copying data: $transfer_info"
  elif echo "$line" | grep -qE "[0-9]+/[0-9]+ tablespaces"; then
    # Tablespace progress: "1/1 tablespaces (100%) finished"
    callback "configuring" "Processing tablespaces: $tablespace_info"
  fi
done
```

### 2. Progress Message Types

The enhanced system sends these types of progress updates:

#### Initial Setup
- "Configuring replication from primary at [IP]..."
- "Creating base backup from primary..."
- "Starting pg_basebackup - initializing backup..."

#### Data Transfer Progress
- "Copying data: 1024/10240 kB (10%), 1/1 tablespace"
- "Copying data: 5120/10240 kB (50%), 1/1 tablespace"
- "Processing tablespaces: 1/1 tablespaces (100%) finished"

#### Completion & Configuration
- "Backup complete - finalizing replica setup..."
- "Base backup completed - setting up replication configuration..."
- "Configuring replica connection to primary..."
- "Setting proper file permissions..."

#### PostgreSQL Startup
- "Starting PostgreSQL replica..."
- "Waiting for PostgreSQL to start up..."
- "PostgreSQL is ready - verifying replication..."

#### Replication Verification
- "Checking if replica is in recovery mode..."
- "Replica is in recovery mode - checking replication connection..."
- "Replication connection established successfully"
- "Replica is fully synchronized (lag: 0 seconds)"

### 3. Error Handling

Progress monitoring includes error detection:

```bash
elif echo "$line" | grep -qiE "(error|failed)"; then
  callback "error" "pg_basebackup error: $line"
  log "ERROR: $line"
fi
```

### 4. ActionCable Integration

All progress updates are automatically broadcast via ActionCable:

- **General updates**: `node_status_updates` stream
- **Node-specific**: `node_status_#{node_id}` stream  
- **Cluster-wide**: `cluster_#{cluster_id}_node_status` stream

### 5. Frontend Display

The JavaScript `node_status_controller.js` automatically receives and displays:

- **Status badges**: Update with current status (configuring → active)
- **Progress messages**: Show detailed step-by-step progress
- **Visual feedback**: Animated updates with scale transitions

## User Experience Improvements

### Before Enhancement
```
Status: "Configuring" 
Message: "Setting up replica..."
[Long wait with no feedback]
Status: "Active"
```

### After Enhancement
```
Status: "Configuring" 
Message: "Starting pg_basebackup - initializing backup..."
Message: "Copying data: 1024/10240 kB (10%), 1/1 tablespace"
Message: "Copying data: 3072/10240 kB (30%), 1/1 tablespace"
Message: "Copying data: 5120/10240 kB (50%), 1/1 tablespace"
Message: "Processing tablespaces: 1/1 tablespaces (100%) finished"
Message: "Backup complete - finalizing replica setup..."
Message: "PostgreSQL is ready - verifying replication..."
Message: "Replica is fully synchronized (lag: 0 seconds)"
Status: "Active"
```

## Testing

Use the test script to simulate progress updates:

```bash
# Test enhanced replica progress updates
bin/rails runner script/test_replica_progress.rb
```

This simulates the complete progress sequence and demonstrates how users will see detailed feedback during replica creation.

## Benefits

1. **Transparency**: Users can see exactly what's happening during replica creation
2. **Progress tracking**: Data transfer progress shows how much has been copied
3. **Issue diagnosis**: Detailed messages help identify where problems occur
4. **User confidence**: Real-time updates reduce anxiety about long-running operations
5. **Better UX**: No more "black box" waiting periods during replica setup

## Implementation Details

The progress monitoring is implemented in `CloudInitService#replica_setup_commands` and uses:

- Bash `while read` loop for real-time output parsing
- Regex patterns to extract progress information
- `${PIPESTATUS[0]}` to check for pg_basebackup failures
- Structured callback messages for consistent UI updates
