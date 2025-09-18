# Database Replica Feature

This document describes the replica functionality added to the DBChest application.

## Overview

The replica feature allows you to create read-only PostgreSQL replicas of your primary database nodes. This helps scale read operations and provides high availability for your database cluster.

**Key Architecture Decision**: All PostgreSQL nodes are created with replica-ready configuration by default. This means every node has the necessary WAL settings, replication user, and archive configuration in place from the start, making replica creation much faster and more reliable.

### Benefits of Replica-Ready Default Configuration

- **Faster Replica Creation**: No need to restart primary nodes when adding replicas
- **Zero Downtime**: Primary nodes only reload configuration (no restart) when adding replicas
- **Security-First**: Replication user and pg_hba.conf entries only created when needed
- **Password Management**: Replication password securely stored and encrypted in database
- **Clean Separation**: Base nodes have WAL configuration but no replication access until replicas are added
- **Consistent Configuration**: Standardized replication settings across all nodes
- **Dynamic Path Detection**: Playbooks automatically detect PostgreSQL configuration paths for maximum portability

## Features

### Node Types
- **Primary Node**: The main database node that handles both read and write operations
- **Replica Node**: A read-only copy that streams changes from the primary node

### Key Capabilities
- Create unlimited replicas from any primary node
- Automatic PostgreSQL streaming replication setup
- Cross-provider replica deployment (replica can be on different provider than primary)
- Visual indication of node types and relationships in the UI
- Automatic replication configuration via Ansible

## How to Use

### Creating a Replica

1. Navigate to a primary node's detail page
2. Click "Add Replica" in the Quick Actions section or the Replicas section
3. Configure the replica:
   - Choose infrastructure provider (can be same or different from primary)
   - Set replica name (auto-generated with pattern: `{primary-name}-replica-{number}`)
   - Adjust provider-specific settings if needed
4. Click "Create Replica" to start the provisioning process

### Replica Provisioning Process

1. **Infrastructure Setup**: Terraform provisions the replica infrastructure
2. **PostgreSQL Installation**: Ansible installs PostgreSQL on the replica node (already replica-ready)
3. **Primary Configuration**: Ansible adds replica-specific pg_hba.conf entries to primary
4. **Replica Configuration**: Ansible configures replica streaming and takes base backup

### UI Indicators

- **Node List**: Shows node type (Primary/Replica) with color-coded badges
- **Node Detail**: Displays replica count for primaries, parent node for replicas  
- **Quick Actions**: "Add Replica" button only appears on primary nodes
- **Replica Section**: Lists all replicas with management options

## Security Model

### Replication Password Management
- **Generated on-demand**: Replication password only created when first replica is added
- **Encrypted storage**: Password encrypted in database using Rails' built-in encryption
- **Reusable**: Same password used for all replicas of a primary node
- **Persistent**: Password survives replica deletion for future replica creation

### Access Control
- **No replication user until needed**: Primary nodes don't have replication user until first replica
- **IP-specific pg_hba.conf entries**: Each replica gets specific IP-based access rules
- **Automatic cleanup**: Replica-specific pg_hba.conf entries removed when replica is deleted
- **Configuration reload only**: No PostgreSQL restarts required for replica management

## Limitations

- Replicas are read-only
- Cannot create replicas of replica nodes (no cascading replication)
- Replication user persists after all replicas are deleted (for performance)

## Ansible Playbooks

### Base Configuration (`create_node.yml` - Updated)
- **All nodes are created replica-ready by default**
- **Dynamically detects PostgreSQL configuration paths** using PostgreSQL's SHOW commands
- Configures WAL settings (wal_level=replica, max_wal_senders, etc.)
- Sets up archive directory and command
- Configures hot standby settings
- **No replication user or pg_hba.conf entries until replicas are added**
- **Portable across different PostgreSQL installations and versions**

### Replica-Specific Playbooks

#### `configure_primary_replication.yml` (Security-Focused)
- Creates replication user only if it doesn't exist
- Adds replica-specific pg_hba.conf entries for the new replica
- Uses stored encrypted replication password from database
- **Only reloads PostgreSQL configuration (no restart)**

#### `configure_replica.yml`
- Takes base backup from primary using stored replication password
- Configures recovery settings for streaming
- Verifies replica configuration (should already be set)
- Starts replica in hot standby mode

#### `cleanup_replica_config.yml` (New)
- Removes replica-specific pg_hba.conf entries when replica is deleted
- Reloads PostgreSQL configuration on primary
- Leaves replication user for future replica creation

## Technical Implementation

### Database Schema
- Added `parent_node_id` foreign key to nodes table
- Self-referential relationship for replica hierarchy

### PostgreSQL Configuration Strategy
- **All nodes are created replica-ready by default** with proper WAL settings
- **Dynamic path detection** using PostgreSQL's `SHOW config_file`, `SHOW hba_file`, and `SHOW data_directory`
- Base `create_node.yml` includes replication configuration (wal_level, max_wal_senders, etc.)
- Replication user only created when first replica is added
- Archive directory and settings configured by default
- **Portable across different PostgreSQL installations** (apt, yum, compiled, Docker, etc.)

### Model Changes
- Added `belongs_to :parent_node` and `has_many :replicas` associations
- Helper methods: `primary?`, `replica?`, `has_replicas?`
- Validation to prevent replica-of-replica creation
- Comment noting replica-ready default configuration

### Controller Changes
- New actions: `add_replica` and `create_replica`
- Validation to ensure only primary nodes can have replicas
- Updated CreateService to handle replica provisioning with simplified logic

### Routes
- `GET /clusters/:cluster_id/nodes/:id/add_replica`
- `POST /clusters/:cluster_id/nodes/:id/create_replica`
