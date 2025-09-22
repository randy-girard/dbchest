# Enhanced Replica Setup - Bug Fixes

## Issues Addressed

### 1. pg_basebackup Directory Permission Error
**Error**: `could not change directory to "/root": Permission denied`

**Root Cause**: `pg_basebackup` was running from `/root` directory which the `postgres` user cannot access.

**Fix**: Run `pg_basebackup` from the postgres home directory:
```bash
# Before (problematic)
sudo -u postgres pg_basebackup -h primary_ip ...

# After (fixed)
sudo -u postgres bash -c "cd /var/lib/postgresql && pg_basebackup -h primary_ip ..."
```

### 2. Missing pg_hba.conf Replication Entry
**Error**: `FATAL: no pg_hba.conf entry for replication connection from host "10.0.0.231", user "replication", SSL on`

**Root Cause**: Primary node wasn't configured with proper `pg_hba.conf` entries for replication connections.

**Fix**: Enhanced primary setup to include replication configuration:
```bash
# Add replication entries to pg_hba.conf
cat >> /etc/postgresql/*/main/pg_hba.conf << EOF

# Replication connections
host    replication     replication     10.0.0.0/8             md5
host    replication     replication     192.168.0.0/16         md5
host    replication     replication     172.16.0.0/12          md5
local   replication     replication                             md5
EOF
```

### 3. JSON Parsing Error in Callbacks
**Error**: `JSON::ParserError (expected ',' or '}' after object value, got: '10.0.0.231",' at line 1 column 143)`

**Root Cause**: Callback messages contained unescaped quotes and special characters that broke JSON parsing.

**Fix**: Added proper JSON escaping in callback function:
```bash
# Escape JSON special characters in the message
escaped_message=$(echo "$message" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g; s/\\t/\\\\t/g; s/\\n/\\\\n/g; s/\\r/\\\\r/g')

# Use escaped message in JSON
curl -d "{\\"status\\": \\"$status\\", \\"message\\": \\"$escaped_message\\"}" ...
```

### 4. Missing Replication User
**Root Cause**: Primary nodes weren't automatically creating the replication user.

**Fix**: Enhanced primary setup to create replication user:
```bash
# Create replication user with password
sudo -u postgres psql -c "CREATE USER replication REPLICATION LOGIN CONNECTION LIMIT 10 PASSWORD '#{replication_password}';"
```

## Enhanced Primary Node Setup

The primary node setup now includes comprehensive replication configuration:

### PostgreSQL Configuration
```bash
echo "wal_level = replica" >> /etc/postgresql/*/main/postgresql.conf
echo "max_wal_senders = 10" >> /etc/postgresql/*/main/postgresql.conf
echo "max_replication_slots = 10" >> /etc/postgresql/*/main/postgresql.conf
echo "archive_mode = on" >> /etc/postgresql/*/main/postgresql.conf
echo "listen_addresses = '*'" >> /etc/postgresql/*/main/postgresql.conf
```

### Network Access Configuration
- Allows replication connections from common private network ranges
- Supports both SSL and non-SSL connections
- Uses MD5 authentication for security

### Sample Database
- Creates `dbchest_sample` database with test data
- Provides immediate data for replication testing

## Enhanced Replica Setup

### Pre-flight Checks
1. **Connectivity Test**: Verifies primary is reachable on port 5432
2. **Authentication Test**: Confirms replication user credentials work
3. **Early Failure**: Exits immediately if primary isn't ready

### Progress Monitoring Improvements
- **Directory Fix**: Runs `pg_basebackup` from correct directory
- **Error Detection**: Catches and reports pg_basebackup errors immediately  
- **JSON Safety**: All progress messages are properly escaped for JSON

### Dependencies
- **netcat**: Added for connectivity testing (`nc -z primary_ip 5432`)
- **Enhanced Error Handling**: Better failure detection and reporting

## Testing the Fixes

### 1. Test Script
Run the enhanced test script to verify all improvements:
```bash
bin/rails runner script/test_enhanced_replica_setup.rb
```

### 2. Manual Testing Steps
1. **Create Primary**: Deploy primary node with enhanced configuration
2. **Verify Setup**: Check that replication user and pg_hba.conf entries exist
3. **Create Replica**: Monitor progress messages for proper JSON formatting
4. **Check Connectivity**: Verify replica connects and synchronizes

### 3. Log Monitoring
Monitor logs for these success indicators:
```bash
# Primary setup success
"Replication user verified, starting base backup..."
"Primary node ready for replication connections"

# Replica setup success  
"Testing connection to primary database..."
"Verifying replication user access..."
"Replica is fully synchronized (lag: 0 seconds)"
```

## Backward Compatibility

- All existing nodes continue to work unchanged
- Enhanced setup only applies to newly created nodes
- Existing replicas can be recreated to benefit from improvements

## Security Improvements

- Replication user has limited privileges (REPLICATION only)
- Connection limits prevent resource exhaustion
- Network access restricted to private IP ranges
- Strong random passwords for all database users

The enhanced setup addresses all the major issues encountered during replica creation and provides a more robust, transparent, and reliable replication process.
