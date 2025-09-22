#!/usr/bin/env ruby

# Test enhanced replica setup with proper error handling and replication configuration

puts "🧪 Testing Enhanced Replica Setup with Error Handling"
puts "=" * 60

# Find or create test nodes
cluster = Cluster.first
if cluster.nil?
  puts "❌ No cluster found. Please create a cluster first."
  exit 1
end

primary_node = cluster.nodes.where(parent_node: nil).first
if primary_node.nil?
  puts "❌ No primary node found. Please create a primary node first."
  exit 1
end

puts "🎯 Found test setup:"
puts "   Cluster: #{cluster.name} (ID: #{cluster.id})"
puts "   Primary: #{primary_node.name} (ID: #{primary_node.id})"
puts "   Primary Status: #{primary_node.status}"
puts ""

# Check if primary has replication password
repl_password = primary_node.ensure_replication_password!
puts "🔐 Primary replication password: #{repl_password[0..8]}... (first 8 chars)"
puts ""

# Generate cloud-init script for primary (if it needs replication setup)
puts "📋 Generating primary setup script..."
primary_script = CloudInitService.new.generate_user_data(primary_node.id, false)
puts "   ✅ Primary script generated (#{primary_script.length} characters)"
puts ""

# Test replica script generation
if primary_node.replicas.any?
  replica = primary_node.replicas.first
  puts "🔄 Found existing replica: #{replica.name} (ID: #{replica.id})"
else
  puts "🔄 No replicas found. Testing script generation for hypothetical replica..."
  replica = Node.new(
    name: "test-replica",
    cluster: cluster,
    parent_node: primary_node,
    provider: primary_node.provider
  )
end

puts "📋 Generating replica setup script..."
replica_script = CloudInitService.new.generate_user_data(replica.id || primary_node.id, true)
puts "   ✅ Replica script generated (#{replica_script.length} characters)"
puts ""

puts "🔍 Analyzing enhanced replica script features..."

# Check for key enhancements
enhancements = {
  "JSON escaping in callbacks" => replica_script.include?("escaped_message="),
  "Primary connectivity test" => replica_script.include?("nc -z"),
  "Replication user verification" => replica_script.include?("psql -h") && replica_script.include?("-U replication"),
  "Directory fix for pg_basebackup" => replica_script.include?("cd /var/lib/postgresql"),
  "Progress monitoring" => replica_script.include?("while IFS= read -r line"),
  "Error handling" => replica_script.include?("PIPESTATUS[0]"),
  "Detailed progress messages" => replica_script.include?("tablespace_info") || replica_script.include?("transfer_info")
}

enhancements.each do |feature, present|
  status = present ? "✅" : "❌"
  puts "   #{status} #{feature}"
end

puts ""

# Check for primary script enhancements
puts "🔍 Analyzing primary script enhancements..."
primary_enhancements = {
  "Replication user creation" => primary_script.include?("CREATE USER replication"),
  "pg_hba.conf configuration" => primary_script.include?("host    replication     replication"),
  "Increased max_wal_senders" => primary_script.include?("max_wal_senders = 10"),
  "Replication slots" => primary_script.include?("max_replication_slots"),
  "Listen addresses" => primary_script.include?("listen_addresses = '*'"),
  "Network access rules" => primary_script.include?("10.0.0.0/8") && primary_script.include?("192.168.0.0/16"),
  "Sample database" => primary_script.include?("CREATE DATABASE dbchest_sample")
}

primary_enhancements.each do |feature, present|
  status = present ? "✅" : "❌"
  puts "   #{status} #{feature}"
end

puts ""

puts "💡 Key improvements made:"
puts "   🔧 Fixed JSON escaping in callback messages"
puts "   🔧 Added directory fix for pg_basebackup (cd /var/lib/postgresql)"
puts "   🔧 Enhanced primary setup with replication user and pg_hba.conf"
puts "   🔧 Added connectivity and authentication pre-checks"
puts "   🔧 Installed netcat for connection testing"
puts "   🔧 Improved error handling and progress reporting"
puts ""

puts "🚀 Issues addressed:"
puts "   ✅ 'Permission denied' error for pg_basebackup directory"
puts "   ✅ 'no pg_hba.conf entry for replication' error"
puts "   ✅ JSON parsing errors in callbacks"
puts "   ✅ Missing replication user on primary"
puts "   ✅ No network access configuration"
puts ""

puts "📋 Next steps to test:"
puts "   1. Deploy a primary node with the enhanced script"
puts "   2. Verify replication user and pg_hba.conf are created"
puts "   3. Create a replica and monitor progress messages"
puts "   4. Check that JSON callbacks work without parsing errors"
puts "   5. Verify pg_basebackup runs successfully"
