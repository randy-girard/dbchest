ProviderType.find_or_create_by(
  name: "Proxmox",
  key: "proxmox"
)

provider = ProviderType.find_by(key: "proxmox")
provider.provider_type_options.find_or_create_by(
  key: "api_url",
  label: "API URL",
  required: true,
  sensitive: true
)
provider.provider_type_options.find_or_create_by(
  key: "username",
  label: "Username",
  required: true,
  sensitive: true
)
provider.provider_type_options.find_or_create_by(
  key: "password",
  label: "Password",
  required: true,
  sensitive: true
)

provider.provider_type_node_options.find_or_create_by(
  key: "template_storage",
  label: "Storage",
  required: true
)
provider.provider_type_node_options.find_or_create_by(
  key: "template_template",
  label: "Template",
  required: true
)

provider.provider_type_node_options.find_or_create_by(
  key: "disk_size",
  label: "Disk Size",
  required: true
)
provider.provider_type_node_options.find_or_create_by(
  key: "node",
  label: "Node",
  required: true
)
provider.provider_type_node_options.find_or_create_by(
  key: "storage",
  label: "Storage",
  required: true
)
provider.provider_type_node_options.find_or_create_by(
  key: "ip_address",
  label: "IP Address",
  required: true
)
provider.provider_type_node_options.find_or_create_by(
  key: "gateway",
  label: "Gateway",
  required: true
)

# Create DigitalOcean Provider Type
digitalocean_provider = ProviderType.find_or_create_by(
  name: "DigitalOcean",
  key: "digitalocean"
)

digitalocean_provider.provider_type_options.find_or_create_by(
  key: "api_token",
  label: "API Token",
  required: true,
  sensitive: true
)

digitalocean_provider.provider_type_node_options.find_or_create_by(
  key: "region",
  label: "Region",
  required: true
)
digitalocean_provider.provider_type_node_options.find_or_create_by(
  key: "size",
  label: "Droplet Size",
  required: true
)
digitalocean_provider.provider_type_node_options.find_or_create_by(
  key: "image",
  label: "Image",
  required: true
)
digitalocean_provider.provider_type_node_options.find_or_create_by(
  key: "ssh_key_id",
  label: "SSH Key",
  required: false
)
digitalocean_provider.provider_type_node_options.find_or_create_by(
  key: "vpc_uuid",
  label: "VPC UUID",
  required: false
)

# Create Database Types
postgresql_type = DatabaseType.find_or_create_by(
  name: "PostgreSQL",
  slug: "postgresql"
)

postgresql_type.database_type_versions.find_or_create_by(
  version: "15",
  install_command: "wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && echo 'deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main' > /etc/apt/sources.list.d/pgdg.list && apt-get update && apt-get install -y postgresql-15 postgresql-client-15",
  default_port: 5432,
  service_name: "postgresql",
  is_default: true
)

postgresql_type.database_type_versions.find_or_create_by(
  version: "14",
  install_command: "wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && echo 'deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main' > /etc/apt/sources.list.d/pgdg.list && apt-get update && apt-get install -y postgresql-14 postgresql-client-14",
  default_port: 5432,
  service_name: "postgresql",
  is_default: false
)

mysql_type = DatabaseType.find_or_create_by(
  name: "MySQL",
  slug: "mysql"
)

mysql_type.database_type_versions.find_or_create_by(
  version: "8.0",
  install_command: "apt-get update && apt-get install -y mysql-server mysql-client",
  default_port: 3306,
  service_name: "mysql",
  is_default: true
)

mysql_type.database_type_versions.find_or_create_by(
  version: "5.7",
  install_command: "apt-get update && apt-get install -y mysql-server-5.7 mysql-client-5.7",
  default_port: 3306,
  service_name: "mysql",
  is_default: false
)

mongodb_type = DatabaseType.find_or_create_by(
  name: "MongoDB",
  slug: "mongodb"
)

mongodb_type.database_type_versions.find_or_create_by(
  version: "7.0",
  install_command: "wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | apt-key add - && echo 'deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse' | tee /etc/apt/sources.list.d/mongodb-org-7.0.list && apt-get update && apt-get install -y mongodb-org=7.0.* mongodb-org-database=7.0.* mongodb-org-server=7.0.* mongodb-org-mongos=7.0.* mongodb-org-tools=7.0.*",
  default_port: 27017,
  service_name: "mongod",
  is_default: true,
  config_template: <<~TEMPLATE
    # mongod.conf

    # for documentation of all options, see:
    #   http://docs.mongodb.org/manual/reference/configuration-options/

    # Where and how to store data.
    storage:
      dbPath: /var/lib/mongodb
      journal:
        enabled: true

    # where to write logging data.
    systemLog:
      destination: file
      logAppend: true
      path: /var/log/mongodb/mongod.log

    # network interfaces
    net:
      port: <%= default_port %>
      bindIp: <%= bind_ip || '127.0.0.1' %>

    # how the process runs
    processManagement:
      timeZoneInfo: /usr/share/zoneinfo

    <% if replica_set_name %>
    replication:
      replSetName: <%= replica_set_name %>
    <% end %>

    #security:

    #operationProfiling:

    #sharding:

    ## Enterprise-Only Options:

    #auditLog:

    #snmp:
  TEMPLATE
)

mongodb_type.database_type_versions.find_or_create_by(
  version: "6.0",
  install_command: "wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add - && echo 'deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/6.0 multiverse' | tee /etc/apt/sources.list.d/mongodb-org-6.0.list && apt-get update && apt-get install -y mongodb-org=6.0.* mongodb-org-database=6.0.* mongodb-org-server=6.0.* mongodb-org-mongos=6.0.* mongodb-org-tools=6.0.*",
  default_port: 27017,
  service_name: "mongod",
  is_default: false,
  config_template: <<~TEMPLATE
    # mongod.conf

    # for documentation of all options, see:
    #   http://docs.mongodb.org/manual/reference/configuration-options/

    # Where and how to store data.
    storage:
      dbPath: /var/lib/mongodb
      journal:
        enabled: true

    # where to write logging data.
    systemLog:
      destination: file
      logAppend: true
      path: /var/log/mongodb/mongod.log

    # network interfaces
    net:
      port: <%= default_port %>
      bindIp: <%= bind_ip || '127.0.0.1' %>

    # how the process runs
    processManagement:
      timeZoneInfo: /usr/share/zoneinfo

    <% if replica_set_name %>
    replication:
      replSetName: <%= replica_set_name %>
    <% end %>

    #security:

    #operationProfiling:

    #sharding:

    ## Enterprise-Only Options:

    #auditLog:

    #snmp:
  TEMPLATE
)

cassandra_type = DatabaseType.find_or_create_by(
  name: "Apache Cassandra",
  slug: "cassandra"
)

cassandra_type.database_type_versions.find_or_create_by(
  version: "4.0",
  install_command: "wget -qO - https://downloads.apache.org/cassandra/KEYS | apt-key add - && echo 'deb https://downloads.apache.org/cassandra/debian 40x main' | tee -a /etc/apt/sources.list.d/cassandra.sources.list && apt-get update && apt-get install -y cassandra cassandra-tools",
  default_port: 9042,
  service_name: "cassandra",
  is_default: true,
  config_template: <<~TEMPLATE
    # Basic Cassandra Configuration Template
    cluster_name: '<%= cluster_name || "dbchest_cluster" %>'
    num_tokens: 256

    # Seed nodes
    seed_provider:
        - class_name: org.apache.cassandra.locator.SimpleSeedProvider
          parameters:
              - seeds: "<%= seeds || '127.0.0.1' %>"

    # Network settings
    listen_address: <%= listen_address || '127.0.0.1' %>
    rpc_address: 0.0.0.0
    broadcast_rpc_address: <%= listen_address || '127.0.0.1' %>

    # Storage settings
    data_file_directories:
        - /var/lib/cassandra/data
    commitlog_directory: /var/lib/cassandra/commitlog
    saved_caches_directory: /var/lib/cassandra/saved_caches

    # Network ports
    storage_port: 7000
    ssl_storage_port: 7001
    native_transport_port: <%= default_port %>

    # Snitch
    endpoint_snitch: GossipingPropertyFileSnitch

    # Auto bootstrap for new nodes
    auto_bootstrap: <%= auto_bootstrap || 'true' %>

    # Basic performance settings
    concurrent_reads: 32
    concurrent_writes: 32
    concurrent_counter_writes: 32

    # Compaction
    compaction_throughput_mb_per_sec: 16

    # Memtable settings
    memtable_allocation_type: heap_buffers

    # Commit log settings
    commitlog_sync: periodic
    commitlog_sync_period_in_ms: 10000
    commitlog_segment_size_in_mb: 32

    # Authentication and authorization
    authenticator: AllowAllAuthenticator
    authorizer: AllowAllAuthorizer
    role_manager: CassandraRoleManager

    # Partitioner
    partitioner: org.apache.cassandra.dht.Murmur3Partitioner

    # Disk failure policy
    disk_failure_policy: stop
    commit_failure_policy: stop

    # Key cache
    key_cache_size_in_mb:
    key_cache_save_period: 14400

    # Row cache
    row_cache_size_in_mb: 0
    row_cache_save_period: 0

    # Counter cache
    counter_cache_size_in_mb:
    counter_cache_save_period: 7200

    # Incremental backups
    incremental_backups: false
    snapshot_before_compaction: false
    auto_snapshot: true

    # Tombstone settings
    tombstone_warn_threshold: 1000
    tombstone_failure_threshold: 100000

    # Batch size settings
    batch_size_warn_threshold_in_kb: 5
    batch_size_fail_threshold_in_kb: 50

    # GC settings
    gc_warn_threshold_in_ms: 1000

    # Network settings
    start_native_transport: true
    start_rpc: false
    rpc_keepalive: true
    rpc_server_type: sync

    # Internode compression
    internode_compression: dc
    inter_dc_tcp_nodelay: false

    # Encryption (disabled by default)
    server_encryption_options:
        internode_encryption: none
        keystore: conf/.keystore
        keystore_password: cassandra
        truststore: conf/.truststore
        truststore_password: cassandra

    client_encryption_options:
        enabled: false
        optional: false
        keystore: conf/.keystore
        keystore_password: cassandra
  TEMPLATE
)

cassandra_type.database_type_versions.find_or_create_by(
  version: "3.11",
  install_command: "wget -qO - https://downloads.apache.org/cassandra/KEYS | apt-key add - && echo 'deb https://downloads.apache.org/cassandra/debian 311x main' | tee -a /etc/apt/sources.list.d/cassandra.sources.list && apt-get update && apt-get install -y cassandra cassandra-tools",
  default_port: 9042,
  service_name: "cassandra",
  is_default: false,
  config_template: <<~TEMPLATE
    # Basic Cassandra Configuration Template (3.11)
    cluster_name: '<%= cluster_name || "dbchest_cluster" %>'
    num_tokens: 256

    # Seed nodes
    seed_provider:
        - class_name: org.apache.cassandra.locator.SimpleSeedProvider
          parameters:
              - seeds: "<%= seeds || '127.0.0.1' %>"

    # Network settings
    listen_address: <%= listen_address || '127.0.0.1' %>
    rpc_address: 0.0.0.0
    broadcast_rpc_address: <%= listen_address || '127.0.0.1' %>

    # Storage settings
    data_file_directories:
        - /var/lib/cassandra/data
    commitlog_directory: /var/lib/cassandra/commitlog
    saved_caches_directory: /var/lib/cassandra/saved_caches

    # Network ports
    storage_port: 7000
    ssl_storage_port: 7001
    native_transport_port: <%= default_port %>

    # Snitch
    endpoint_snitch: GossipingPropertyFileSnitch

    # Auto bootstrap for new nodes
    auto_bootstrap: <%= auto_bootstrap || 'true' %>

    # Basic performance settings
    concurrent_reads: 32
    concurrent_writes: 32
    concurrent_counter_writes: 32

    # Compaction
    compaction_throughput_mb_per_sec: 16

    # Memtable settings
    memtable_allocation_type: heap_buffers

    # Commit log settings
    commitlog_sync: periodic
    commitlog_sync_period_in_ms: 10000
    commitlog_segment_size_in_mb: 32

    # Authentication and authorization
    authenticator: AllowAllAuthenticator
    authorizer: AllowAllAuthorizer
    role_manager: CassandraRoleManager

    # Partitioner
    partitioner: org.apache.cassandra.dht.Murmur3Partitioner

    # Disk failure policy
    disk_failure_policy: stop
    commit_failure_policy: stop

    # Key cache
    key_cache_size_in_mb:
    key_cache_save_period: 14400

    # Row cache
    row_cache_size_in_mb: 0
    row_cache_save_period: 0

    # Counter cache
    counter_cache_size_in_mb:
    counter_cache_save_period: 7200

    # Incremental backups
    incremental_backups: false
    snapshot_before_compaction: false
    auto_snapshot: true

    # Tombstone settings
    tombstone_warn_threshold: 1000
    tombstone_failure_threshold: 100000

    # Batch size settings
    batch_size_warn_threshold_in_kb: 5
    batch_size_fail_threshold_in_kb: 50

    # GC settings
    gc_warn_threshold_in_ms: 1000

    # Network settings
    start_native_transport: true
    start_rpc: false
    rpc_keepalive: true
    rpc_server_type: sync

    # Internode compression
    internode_compression: dc
    inter_dc_tcp_nodelay: false

    # Encryption (disabled by default)
    server_encryption_options:
        internode_encryption: none
        keystore: conf/.keystore
        keystore_password: cassandra
        truststore: conf/.truststore
        truststore_password: cassandra

    client_encryption_options:
        enabled: false
        optional: false
        keystore: conf/.keystore
        keystore_password: cassandra
  TEMPLATE
)
