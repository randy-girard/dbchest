# Database Types and Versions Feature

This document describes the new database types and versions system that allows clusters to support multiple database types (PostgreSQL, MySQL, etc.) and individual nodes to run different versions of their cluster's database type.

## Architecture Overview

### Database Schema

1. **DatabaseType** - Defines the type of database (PostgreSQL, MySQL, etc.)
   - `name`: Human-readable name (e.g., "PostgreSQL", "MySQL")
   - `slug`: Machine-readable identifier (e.g., "postgresql", "mysql")

2. **DatabaseTypeVersion** - Defines specific versions and installation details
   - `database_type_id`: Foreign key to DatabaseType
   - `version`: Version string (e.g., "15", "16", "8.0")
   - `install_command`: Shell command to install this version
   - `default_port`: Default port for this database version
   - `service_name`: System service name (e.g., "postgresql", "mysql")
   - `data_directory_pattern`: Path pattern for data directory
   - `config_file_pattern`: Path pattern for configuration file
   - `is_default`: Whether this is the default version for the database type

3. **Cluster** - Associated with a DatabaseType
   - `database_type_id`: Foreign key to DatabaseType

4. **Node** - Associated with a DatabaseTypeVersion
   - `database_type_version_id`: Foreign key to DatabaseTypeVersion
   - Must match the cluster's database type

### Model Relationships

```
DatabaseType (1) → (many) DatabaseTypeVersion
DatabaseType (1) → (many) Cluster
Cluster (1) → (many) Node
DatabaseTypeVersion (1) → (many) Node
```

### Validation Rules

- Nodes can only select versions that match their cluster's database type
- Each database type can have one default version
- Database type slugs must be unique and follow naming conventions

## Frontend Changes

### Cluster Form
- Added dropdown to select database type when creating/editing clusters
- Dynamically loads available database types from the database

### Node Form
- Added dropdown to select database version when creating/editing nodes
- Dynamically filters available versions based on cluster's database type
- Shows replication compatibility warnings for mixed versions

## Backend Changes

### Cloud-Init Service
- Updated `CloudInitService` to use node's database type version information
- Dynamic PostgreSQL version installation based on node configuration
- Version-aware configuration file paths

### Ansible Integration
- All Ansible playbooks now receive `postgresql_version` variable
- Updated service calls to pass version information
- Version-specific configuration paths in all playbooks

### Replication Logic
- Added methods to determine replication compatibility between versions
- Automatic detection of required replication method (streaming vs logical)
- Support for cross-version replication using logical replication when needed

## Replication Strategy

### Same Version Replication
- Uses streaming replication (faster, more efficient)
- Direct pg_basebackup from primary to replica

### Cross-Version Replication  
- Automatically uses logical replication when versions differ
- Supports upgrading/downgrading scenarios
- Requires PostgreSQL 10+ for logical replication support

### Compatibility Matrix

| Primary Version | Replica Version | Replication Method | Supported |
|----------------|----------------|-------------------|-----------|
| 15             | 15             | Streaming         | ✅        |
| 15             | 16             | Logical           | ✅        |
| 14             | 15             | Logical           | ✅        |
| 12             | 13             | Streaming         | ✅        |
| 9.x            | 10+            | Not Supported     | ❌        |

## Available Database Types

### PostgreSQL Versions
- PostgreSQL 12
- PostgreSQL 13  
- PostgreSQL 14
- PostgreSQL 15 (default)
- PostgreSQL 16

### MySQL Versions (Future Support)
- MySQL 8.0 (prepared for future implementation)

## Configuration Examples

### Creating a PostgreSQL 16 Cluster
1. Select "PostgreSQL" as database type in cluster form
2. Create nodes and select "PostgreSQL 16" from version dropdown

### Mixed Version Setup
1. Create cluster with PostgreSQL type
2. Create primary node with PostgreSQL 15
3. Create replica node with PostgreSQL 16
4. System automatically uses logical replication

## Installation Commands

Each database type version includes specific installation commands:

```bash
# PostgreSQL 15
DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-15 postgresql-contrib-15

# PostgreSQL 16  
DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-16 postgresql-contrib-16

# MySQL 8.0 (future)
DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server-8.0
```

## Migration Notes

- Existing clusters automatically assigned to PostgreSQL database type
- Existing nodes automatically assigned to PostgreSQL 15 (current default)
- Backward compatibility maintained for existing deployments
- No breaking changes to existing API or functionality

## Future Enhancements

1. **Additional Database Types**
   - MySQL support
   - MariaDB support  
   - MongoDB support

2. **Advanced Replication**
   - Cascading replication
   - Multi-master setups
   - Cross-database-type replication

3. **Version Management**
   - Automated version upgrades
   - Version rollback capabilities
   - Migration tools between versions

## Developer Notes

### Adding New Database Types
1. Create new DatabaseType record with name and slug
2. Add DatabaseTypeVersion records with installation commands
3. Update CloudInitService for new database type
4. Create Ansible playbooks in `lib/ansible/{slug}/` directory

### Adding New Versions
1. Create new DatabaseTypeVersion record
2. Test installation commands
3. Verify replication compatibility
4. Update documentation

### Testing
- All existing functionality should continue working
- New clusters can select database types
- New nodes can select compatible versions
- Replication works between compatible versions
