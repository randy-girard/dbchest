namespace :postgresql do
  desc "Reload PostgreSQL configuration on a node"
  task :reload_config, [ :node_id ] => :environment do |t, args|
    node_id = args[:node_id]

    unless node_id
      puts "Usage: rake postgresql:reload_config[NODE_ID]"
      puts "Example: rake postgresql:reload_config[1]"
      exit 1
    end

    node = Node.find_by(id: node_id)
    unless node
      puts "Error: Node #{node_id} not found"
      exit 1
    end

    unless node.database_type_slug == "postgresql"
      puts "Error: Node #{node_id} is not a PostgreSQL node (type: #{node.database_type_slug})"
      exit 1
    end

    puts "Reloading PostgreSQL configuration on node #{node.id} (#{node.name})..."

    result = AnsibleRunService.new.perform(
      node.id,
      "reload_pg_hba.yml",
      vars: {}
    )

    if result[:success]
      puts "✅ Successfully reloaded PostgreSQL configuration"
    else
      puts "❌ Failed to reload PostgreSQL configuration"
      puts "Error: #{result[:error]}" if result[:error]
      exit 1
    end
  end

  desc "Add replica-specific replication entry to primary node"
  task :add_replica_entry, [ :primary_node_id, :replica_node_id ] => :environment do |t, args|
    primary_node_id = args[:primary_node_id]
    replica_node_id = args[:replica_node_id]

    unless primary_node_id && replica_node_id
      puts "Usage: rake postgresql:add_replica_entry[PRIMARY_NODE_ID,REPLICA_NODE_ID]"
      puts "Example: rake postgresql:add_replica_entry[1,2]"
      exit 1
    end

    primary_node = Node.find_by(id: primary_node_id)
    replica_node = Node.find_by(id: replica_node_id)

    unless primary_node
      puts "Error: Primary node #{primary_node_id} not found"
      exit 1
    end

    unless replica_node
      puts "Error: Replica node #{replica_node_id} not found"
      exit 1
    end

    unless primary_node.database_type_slug == "postgresql"
      puts "Error: Primary node is not a PostgreSQL node"
      exit 1
    end

    unless primary_node.primary?
      puts "Error: Node #{primary_node_id} is not a primary node"
      exit 1
    end

    replica_ip = replica_node.get_ip_address
    unless replica_ip
      puts "Error: Replica node has no IP address"
      exit 1
    end

    puts "Adding replica-specific replication entry to primary #{primary_node.id} for replica #{replica_node.id} (#{replica_ip})..."

    result = AnsibleRunService.new.perform(
      primary_node.id,
      "configure_primary_replication.yml",
      vars: {
        replica_ip: replica_ip,
        replica_node_name: replica_node.name,
        replication_password: primary_node.get_replication_password,
        postgresql_version: primary_node.database_type_version&.version || "15"
      }
    )

    if result[:success]
      puts "✅ Successfully added replication entry for replica #{replica_ip}"
    else
      puts "❌ Failed to add replication entry"
      puts "Error: #{result[:error]}" if result[:error]
      exit 1
    end
  end
end
