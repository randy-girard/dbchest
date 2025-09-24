#!/bin/bash
set -e

# PostgreSQL Database Setup Script
log "Setting up PostgreSQL database..."
callback "installing" "Installing PostgreSQL..."

# Update package lists
apt-get update

# Install PostgreSQL and required packages
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  postgresql-12 \
  postgresql-client-12 \
  postgresql-contrib-12

# Store root password
echo "{{ROOT_PASSWORD}}" > /var/lib/postgresql/.dbchest_password

# Configure PostgreSQL authentication
log "Configuring PostgreSQL authentication..."

# Set postgres user password
sudo -u postgres psql -c "ALTER USER postgres PASSWORD '{{ROOT_PASSWORD}}';"

# Configure pg_hba.conf for authentication
PG_HBA="/etc/postgresql/12/main/pg_hba.conf"
cp "$PG_HBA" "$PG_HBA.backup"

# Update pg_hba.conf
cat > "$PG_HBA" << 'CONFIG_FILE'
local   all             postgres                                peer
local   all             all                                     md5
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
host    all             all             0.0.0.0/0               md5
host    replication     all             0.0.0.0/0               md5
CONFIG_FILE

# Configure postgresql.conf
log "Configuring PostgreSQL settings..."
PG_CONF="/etc/postgresql/12/main/postgresql.conf"
cp "$PG_CONF" "$PG_CONF.backup"

# Basic configuration
echo "listen_addresses = '*'" >> "$PG_CONF"
echo "port = 5432" >> "$PG_CONF"
echo "max_connections = 100" >> "$PG_CONF"
echo "shared_buffers = 128MB" >> "$PG_CONF"
echo "logging_collector = on" >> "$PG_CONF"
echo "log_directory = 'log'" >> "$PG_CONF"
echo "log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'" >> "$PG_CONF"
echo "log_statement = 'all'" >> "$PG_CONF"

# Restart PostgreSQL to apply configuration
systemctl restart postgresql
systemctl enable postgresql

# Verify PostgreSQL is running
systemctl is-active postgresql

log "PostgreSQL setup completed successfully"
callback "active" "Database node is ready"
