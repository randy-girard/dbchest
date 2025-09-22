# Cloud-Init Integration

This document describes the integration of cloud-init for server provisioning instead of Ansible for the initial server setup process.

## Overview

The system has been modified to use cloud-init for the initial PostgreSQL installation and basic configuration, while keeping Ansible for more complex replication configuration tasks.

## Key Components

### 1. CloudInitService (`app/services/cloud_init_service.rb`)
- Generates shell scripts that perform the initial server setup
- Handles both primary and replica node configurations
- Includes callback mechanisms to report status back to the application

### 2. NodeStatusCallbacksController (`app/controllers/node_status_callbacks_controller.rb`) 
- API endpoint for cloud-init scripts to report status updates
- Route: `POST /nodes/:id/status_callback`
- Automatically triggers replica configuration when a replica node becomes active

### 3. ReplicaConfigurationService (`app/services/replica_configuration_service.rb`) 
- Handles the Ansible-based configuration for replication setup on primary nodes
- Called synchronously during replica creation (before cloud-init runs)

### 4. Updated CreateService (`app/services/create_service.rb`)
- No longer blocks on Ansible execution for initial setup
- For replicas: configures primary synchronously, then provisions replica with full setup
- Terraform provisioning includes cloud-init setup

## Flow

### Primary Node Creation
1. User creates a node through the web interface
2. `CreateService` is called via Sidekiq
3. `TerraformCreateService` provisions infrastructure with cloud-init script
4. Cloud-init script installs PostgreSQL and configures for replication readiness
5. Cloud-init script reports status via callback API
6. Node becomes 'active'

### Replica Node Creation (Simplified)
1. User creates a replica through the web interface
2. `CreateService` is called with `is_replica = true`
3. **First**: Ansible configures the primary node for the new replica (replication user, pg_hba.conf, replication slot)
4. **Then**: `TerraformCreateService` provisions replica infrastructure with full replication setup in cloud-init
5. Cloud-init script:
   - Installs PostgreSQL
   - Creates base backup from primary using pg_basebackup
   - Configures replica to follow primary
   - Starts PostgreSQL in recovery mode
   - Reports status via callback API
6. Replica becomes 'active' and is replicating

## Configuration

### Environment Variables
- `DBCHEST_CALLBACK_HOST`: Host that containers can reach for callbacks (default: `host.docker.internal:3000` in development)
- `APPLICATION_HOST`: Production hostname for callbacks

### Terraform Changes
- Added `cloud_init_user_data` variable
- Added `ssh_private_key` variable for provisioning
- Added provisioners to deploy and run the setup script

## Benefits

1. **Non-blocking**: Background jobs don't wait for long-running setup processes
2. **Resilient**: Cloud-init runs independently and can retry on failure
3. **Callback-driven**: Real-time status updates via API callbacks
4. **Hybrid approach**: Simple tasks use cloud-init, complex tasks use Ansible
5. **Replica support**: Proper handling of replica configuration with primary setup

## Development Notes

- For local development, ensure containers can reach the Rails app at `host.docker.internal:3000`
- Check `/var/log/dbchest-setup.log` on containers for cloud-init script output
- Use the existing ActionCable infrastructure for real-time status updates
- Sidekiq handles background job scheduling and retries

## API Endpoints

### Status Callback
```
POST /nodes/:id/status_callback
Content-Type: application/json

{
  "status": "configuring",
  "message": "Installing PostgreSQL..."
}
```

**Valid statuses**: pending, provisioning, configuring, active, error, destroying, destroyed

## Error Handling

- Cloud-init script failures are reported via callback with status 'error'
- Replica configuration failures are handled by `ReplicaSetupJob` with automatic retries
- All errors are logged and broadcast via ActionCable for real-time updates
