class PopulateDatabaseTypesAndVersions < ActiveRecord::Migration[8.0]
  def up
    # Create PostgreSQL database type
    postgresql_type = DatabaseType.find_or_create_by(
      name: "PostgreSQL",
      slug: "postgresql"
    )

    # PostgreSQL 15 (default)
    postgresql_type.database_type_versions.find_or_create_by(
      version: "15"
    ) do |version|
      version.install_command = <<~CMD.strip
        # Add PostgreSQL APT repository
        wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
        echo "deb http://apt-archive.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-15 postgresql-contrib-15
      CMD
      version.default_port = 5432
      version.service_name = "postgresql"
      version.data_directory_pattern = "/var/lib/postgresql/15/main"
      version.config_file_pattern = "/etc/postgresql/15/main/postgresql.conf"
      version.is_default = true
    end

    # PostgreSQL 17
    postgresql_type.database_type_versions.find_or_create_by(
      version: "17"
    ) do |version|
      version.install_command = <<~CMD.strip
        # Check Ubuntu version and install accordingly
        if [ "$(lsb_release -rs)" = "20.04" ]; then
          echo "PostgreSQL 17 is not available for Ubuntu 20.04. Please use Ubuntu 22.04 or later."
          exit 1
        else
          # Add PostgreSQL APT repository
          wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
          echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
          apt-get update
          DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-17 postgresql-contrib-17
        fi
      CMD
      version.default_port = 5432
      version.service_name = "postgresql"
      version.data_directory_pattern = "/var/lib/postgresql/17/main"
      version.config_file_pattern = "/etc/postgresql/17/main/postgresql.conf"
      version.is_default = false
    end

    # PostgreSQL 16
    postgresql_type.database_type_versions.find_or_create_by(
      version: "16"
    ) do |version|
      version.install_command = <<~CMD.strip
        # Check Ubuntu version and install accordingly
        if [ "$(lsb_release -rs)" = "20.04" ]; then
          echo "PostgreSQL 16 is not available for Ubuntu 20.04. Please use Ubuntu 22.04 or later."
          exit 1
        else
          # Add PostgreSQL APT repository
          wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
          echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
          apt-get update
          DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-16 postgresql-contrib-16
        fi
      CMD
      version.default_port = 5432
      version.service_name = "postgresql"
      version.data_directory_pattern = "/var/lib/postgresql/16/main"
      version.config_file_pattern = "/etc/postgresql/16/main/postgresql.conf"
      version.is_default = false
    end

    # PostgreSQL 14
    postgresql_type.database_type_versions.find_or_create_by(
      version: "14"
    ) do |version|
      version.install_command = <<~CMD.strip
        # Add PostgreSQL APT repository
        wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
        echo "deb http://apt-archive.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-14 postgresql-contrib-14
      CMD
      version.default_port = 5432
      version.service_name = "postgresql"
      version.data_directory_pattern = "/var/lib/postgresql/14/main"
      version.config_file_pattern = "/etc/postgresql/14/main/postgresql.conf"
      version.is_default = false
    end

    # PostgreSQL 13
    postgresql_type.database_type_versions.find_or_create_by(
      version: "13"
    ) do |version|
      version.install_command = "DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-13 postgresql-contrib-13"
      version.default_port = 5432
      version.service_name = "postgresql"
      version.data_directory_pattern = "/var/lib/postgresql/13/main"
      version.config_file_pattern = "/etc/postgresql/13/main/postgresql.conf"
      version.is_default = false
    end

    # PostgreSQL 12
    postgresql_type.database_type_versions.find_or_create_by(
      version: "12"
    ) do |version|
      version.install_command = "DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-12 postgresql-contrib-12"
      version.default_port = 5432
      version.service_name = "postgresql"
      version.data_directory_pattern = "/var/lib/postgresql/12/main"
      version.config_file_pattern = "/etc/postgresql/12/main/postgresql.conf"
      version.is_default = false
    end

    # Create MySQL database type
    mysql_type = DatabaseType.find_or_create_by(
      name: "MySQL",
      slug: "mysql"
    )

    # MySQL 8.0 (default)
    mysql_type.database_type_versions.find_or_create_by(
      version: "8.0"
    ) do |version|
      version.install_command = "apt-get update && apt-get install -y mysql-server mysql-client"
      version.default_port = 3306
      version.service_name = "mysql"
      version.data_directory_pattern = "/var/lib/mysql"
      version.config_file_pattern = "/etc/mysql/mysql.conf.d/mysqld.cnf"
      version.is_default = true
    end

    # MySQL 5.7
    mysql_type.database_type_versions.find_or_create_by(
      version: "5.7"
    ) do |version|
      version.install_command = "apt-get update && apt-get install -y mysql-server-5.7 mysql-client-5.7"
      version.default_port = 3306
      version.service_name = "mysql"
      version.data_directory_pattern = "/var/lib/mysql"
      version.config_file_pattern = "/etc/mysql/mysql.conf.d/mysqld.cnf"
      version.is_default = false
    end

    # Create MongoDB database type
    mongodb_type = DatabaseType.find_or_create_by(
      name: "MongoDB",
      slug: "mongodb"
    )

    # MongoDB 7.0 (default)
    mongodb_type.database_type_versions.find_or_create_by(
      version: "7.0"
    ) do |version|
      version.install_command = "wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | apt-key add - && echo 'deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse' | tee /etc/apt/sources.list.d/mongodb-org-7.0.list && apt-get update && apt-get install -y mongodb-org=7.0.* mongodb-org-database=7.0.* mongodb-org-server=7.0.* mongodb-org-mongos=7.0.* mongodb-org-tools=7.0.*"
      version.default_port = 27017
      version.service_name = "mongod"
      version.data_directory_pattern = "/var/lib/mongodb"
      version.config_file_pattern = "/etc/mongod.conf"
      version.is_default = true
      version.config_template = mongodb_7_config_template
    end

    # MongoDB 6.0
    mongodb_type.database_type_versions.find_or_create_by(
      version: "6.0"
    ) do |version|
      version.install_command = "wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add - && echo 'deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/6.0 multiverse' | tee /etc/apt/sources.list.d/mongodb-org-6.0.list && apt-get update && apt-get install -y mongodb-org=6.0.* mongodb-org-database=6.0.* mongodb-org-server=6.0.* mongodb-org-mongos=6.0.* mongodb-org-tools=6.0.*"
      version.default_port = 27017
      version.service_name = "mongod"
      version.data_directory_pattern = "/var/lib/mongodb"
      version.config_file_pattern = "/etc/mongod.conf"
      version.is_default = false
      version.config_template = mongodb_6_config_template
    end

    # Create Cassandra database type
    cassandra_type = DatabaseType.find_or_create_by(
      name: "Apache Cassandra",
      slug: "cassandra"
    )

    # Cassandra 4.0 (default)
    cassandra_type.database_type_versions.find_or_create_by(
      version: "4.0"
    ) do |version|
      version.install_command = "wget -qO - https://downloads.apache.org/cassandra/KEYS | apt-key add - && echo 'deb https://downloads.apache.org/cassandra/debian 40x main' | tee -a /etc/apt/sources.list.d/cassandra.sources.list && apt-get update && apt-get install -y cassandra cassandra-tools"
      version.default_port = 9042
      version.service_name = "cassandra"
      version.data_directory_pattern = "/var/lib/cassandra/data"
      version.config_file_pattern = "/etc/cassandra/cassandra.yaml"
      version.is_default = true
      version.config_template = cassandra_4_config_template
    end

    # Cassandra 3.11
    cassandra_type.database_type_versions.find_or_create_by(
      version: "3.11"
    ) do |version|
      version.install_command = "wget -qO - https://downloads.apache.org/cassandra/KEYS | apt-key add - && echo 'deb https://downloads.apache.org/cassandra/debian 311x main' | tee -a /etc/apt/sources.list.d/cassandra.sources.list && apt-get update && apt-get install -y cassandra cassandra-tools"
      version.default_port = 9042
      version.service_name = "cassandra"
      version.data_directory_pattern = "/var/lib/cassandra/data"
      version.config_file_pattern = "/etc/cassandra/cassandra.yaml"
      version.is_default = false
      version.config_template = cassandra_3_config_template
    end
  end

  def down
    # Remove all database types and their versions
    DatabaseType.destroy_all
  end

  private

  def mongodb_7_config_template
    <<~TEMPLATE
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
  end

  def mongodb_6_config_template
    <<~TEMPLATE
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
  end

  def cassandra_4_config_template
    <<~TEMPLATE
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
  end

  def cassandra_3_config_template
    # Same as 4.0 for now - can be customized later if needed
    cassandra_4_config_template
  end
end
