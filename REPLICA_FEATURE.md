# Database Replica Feature

This document describes the replica functionality added to the DBChest application.

## Overview

The replica feature allows you to create read-only PostgreSQL replicas of your primary database nodes. This helps scale read operations and provides high availability for your database cluster.

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
2. **PostgreSQL Installation**: Ansible installs PostgreSQL on the replica node
3. **Primary Configuration**: Ansible configures the primary node to allow replication
4. **Replica Configuration**: Ansible sets up the replica to stream from the primary

### UI Indicators

- **Node List**: Shows node type (Primary/Replica) with color-coded badges
- **Node Detail**: Displays replica count for primaries, parent node for replicas  
- **Quick Actions**: "Add Replica" button only appears on primary nodes
- **Replica Section**: Lists all replicas with management options

## Limitations

- Replicas are read-only
- Cannot create replicas of replica nodes (no cascading replication)
- Replica deletion requires manual cleanup of replication configuration

## Ansible Playbooks

The feature includes two new Ansible playbooks:

### `configure_primary_replication.yml`
- Configures WAL settings on primary node
- Creates replication user
- Updates pg_hba.conf for replica access
- Sets up archiving

### `configure_replica.yml`
- Takes base backup from primary
- Configures recovery settings
- Sets up streaming replication
- Starts replica in hot standby mode

## Technical Implementation

### Database Schema
- Added `parent_node_id` foreign key to nodes table
- Self-referential relationship for replica hierarchy

### Model Changes
- Added `belongs_to :parent_node` and `has_many :replicas` associations
- Helper methods: `primary?`, `replica?`, `has_replicas?`
- Validation to prevent replica-of-replica creation

### Controller Changes
- New actions: `add_replica` and `create_replica`
- Validation to ensure only primary nodes can have replicas
- Updated CreateService to handle replica provisioning

### Routes
- `GET /clusters/:cluster_id/nodes/:id/add_replica`
- `POST /clusters/:cluster_id/nodes/:id/create_replica`
