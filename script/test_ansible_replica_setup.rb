#!/usr/bin/env ruby

# Test the enhanced replica setup with Ansible-based primary configuration

puts "🧪 Testing Ansible-Based Primary Configuration for Replicas"
puts "=" * 60

# Check if required components exist
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

# Check if primary has replication password
repl_password = primary_node.ensure_replication_password!
puts "   🔐 Replication password configured: #{repl_password[0..8]}..."
puts ""

puts "🔍 Analyzing new approach..."

# Generate replica script
puts "📋 Generating replica setup script..."
replica_script = CloudInitService.new.generate_user_data(primary_node.id, true)
puts "   ✅ Replica script generated (#{replica_script.length} characters)"

# Check for new features
new_features = {
  "Ansible callback trigger" => replica_script.include?("configure_primary_for_replica"),
  "IP detection" => replica_script.include?("ip route get") || replica_script.include?("hostname -I"),
  "Connection wait loop" => replica_script.include?("for i in {1..30}"),
  "Replication test in loop" => replica_script.include?("psql -h #{primary_node.get_ip_address || 'PRIMARY_IP'} -U replication"),
  "Timeout handling" => replica_script.include?("Timeout waiting for primary"),
  "No SSH complexity" => !replica_script.include?("ssh -o StrictHostKeyChecking"),
  "No broad network access" => !replica_script.include?("10.0.0.0/8")
}

new_features.each do |feature, present|
  status = present ? "✅" : "❌"
  puts "   #{status} #{feature}"
end

puts ""

# Check primary script changes
puts "🔍 Analyzing primary script changes..."
primary_script = CloudInitService.new.generate_user_data(primary_node.id, false)

primary_changes = {
  "No broad pg_hba entries" => !primary_script.include?("10.0.0.0/8"),
  "Replication user still created" => primary_script.include?("CREATE USER replication"),
  "Deferred pg_hba note" => primary_script.include?("pg_hba.conf will be updated when replicas are added")
}

primary_changes.each do |change, present|
  status = present ? "✅" : "❌"
  puts "   #{status} #{change}"
end

puts ""

puts "🤖 Testing Ansible job functionality..."

# Test the job class exists
begin
  job_class = ConfigurePrimaryForReplicaJob
  puts "   ✅ ConfigurePrimaryForReplicaJob class exists"
  
  # Test playbook generation (mock data)
  job = job_class.new
  job.instance_variable_set(:@primary_node, primary_node)
  job.instance_variable_set(:@replica_node, OpenStruct.new(name: "test-replica"))
  job.instance_variable_set(:@replica_ip, "10.0.0.100")
  
  playbook = job.send(:generate_primary_configuration_playbook, "test_password")
  puts "   ✅ Ansible playbook generation works (#{playbook.length} chars)"
  
  # Check playbook contents
  playbook_features = {
    "PostgreSQL user creation" => playbook.include?("postgresql_user:"),
    "pg_hba.conf entries" => playbook.include?("lineinfile:"),
    "Specific IP targeting" => playbook.include?("{{ replica_ip }}/32"),
    "PostgreSQL reload" => playbook.include?("state: reloaded"),
    "Connection testing" => playbook.include?("login_user: replication")
  }
  
  playbook_features.each do |feature, present|
    status = present ? "✅" : "❌"
    puts "     #{status} #{feature}"
  end
  
rescue NameError => e
  puts "   ❌ ConfigurePrimaryForReplicaJob class not found: #{e.message}"
rescue => e
  puts "   ❌ Error testing Ansible job: #{e.message}"
end

puts ""

puts "📋 Testing callback controller enhancement..."

# Check if controller has the new method
begin
  controller = NodeStatusCallbacksController.new
  if controller.private_methods.include?(:handle_configure_primary_for_replica)
    puts "   ✅ Controller has handle_configure_primary_for_replica method"
  else
    puts "   ❌ Controller missing handle_configure_primary_for_replica method"
  end
rescue => e
  puts "   ❌ Error checking controller: #{e.message}"
end

puts ""

puts "🎯 New workflow summary:"
puts "   1. Replica gets its IP address"
puts "   2. Replica sends 'configure_primary_for_replica' callback"
puts "   3. Controller triggers ConfigurePrimaryForReplicaJob with replica IP"
puts "   4. Ansible job adds specific pg_hba.conf entry to primary"
puts "   5. Replica waits and tests connection until primary is ready"
puts "   6. Once connection works, replica proceeds with pg_basebackup"
puts ""

puts "🔐 Security improvements:"
puts "   ✅ No broad network access in pg_hba.conf"
puts "   ✅ Only specific replica IPs are allowed"
puts "   ✅ Entries added only when needed"
puts "   ✅ No complex SSH-based configuration"
puts ""

puts "💡 Benefits:"
puts "   • More secure (specific IPs only)"
puts "   • Cleaner separation of concerns (Ansible handles infrastructure)"
puts "   • Better error handling and retries"
puts "   • No SSH key management between nodes"
puts "   • Proper wait/retry mechanism"
puts ""

puts "🧪 To test this setup:"
puts "   1. Create a primary node with the updated script"
puts "   2. Create a replica node - it should:"
puts "      • Get its IP address"
puts "      • Trigger Ansible job via callback"
puts "      • Wait for primary configuration"
puts "      • Proceed with pg_basebackup once connection works"
