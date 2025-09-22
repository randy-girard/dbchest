#!/usr/bin/env ruby

# Test enhanced replica progress updates via ActionCable

puts "🧪 Testing Enhanced Replica Progress Updates"
puts "=" * 50

# Find a primary node with replicas or create a test scenario
primary_node = Node.joins(:replicas).distinct.first
if primary_node.nil?
  puts "❌ No primary nodes with replicas found."
  puts "💡 Create a replica first, then run this test."
  exit 1
end

replica = primary_node.replicas.first
puts "🎯 Found test setup:"
puts "   Primary: #{primary_node.name} (ID: #{primary_node.id})"
puts "   Replica: #{replica.name} (ID: #{replica.id})"
puts "   Cluster: #{primary_node.cluster.name} (ID: #{primary_node.cluster_id})"
puts "   Current replica status: #{replica.status}"

puts "\n📱 Open the replica node page or cluster page in your browser:"
puts "   Replica URL: /clusters/#{replica.cluster_id}/nodes/#{replica.id}"
puts "   Cluster URL: /clusters/#{replica.cluster_id}/nodes"
puts "   👀 Watch for detailed progress messages"
puts ""

puts "🔄 Simulating pg_basebackup progress updates..."

# Simulate the enhanced progress sequence for replica setup
progress_sequence = [
  { status: 'configuring', message: 'Configuring replication from primary at 10.0.0.10...' },
  { status: 'configuring', message: 'Creating base backup from primary...' },
  { status: 'configuring', message: 'Starting pg_basebackup - initializing backup...' },
  { status: 'configuring', message: 'Copying data: 1024/10240 kB (10%), 1/1 tablespace' },
  { status: 'configuring', message: 'Copying data: 3072/10240 kB (30%), 1/1 tablespace' },
  { status: 'configuring', message: 'Copying data: 5120/10240 kB (50%), 1/1 tablespace' },
  { status: 'configuring', message: 'Processing tablespaces: 1/1 tablespaces (100%) finished' },
  { status: 'configuring', message: 'Backup complete - finalizing replica setup...' },
  { status: 'configuring', message: 'Base backup completed - setting up replication configuration...' },
  { status: 'configuring', message: 'Configuring replica connection to primary...' },
  { status: 'configuring', message: 'Setting proper file permissions...' },
  { status: 'configuring', message: 'Starting PostgreSQL replica...' },
  { status: 'configuring', message: 'Waiting for PostgreSQL to start up...' },
  { status: 'configuring', message: 'PostgreSQL is ready - verifying replication...' },
  { status: 'configuring', message: 'Checking if replica is in recovery mode...' },
  { status: 'configuring', message: 'Replica is in recovery mode - checking replication connection...' },
  { status: 'configuring', message: 'Replication connection established successfully' },
  { status: 'configuring', message: 'Gathering replication status information...' },
  { status: 'configuring', message: 'Replica is fully synchronized (lag: 0 seconds)' },
  { status: 'active', message: 'Node is now active and ready' }
]

progress_sequence.each_with_index do |progress_data, index|
  puts "\n#{index + 1}/#{progress_sequence.length}. #{progress_data[:message]}"
  
  begin
    replica.update_status!(progress_data[:status], progress_data[:message])
    puts "   ✅ Status: '#{progress_data[:status]}'"
    puts "   📡 ActionCable broadcast sent"
    
    # Shorter delays for steps in the middle of the process
    if progress_data[:message].include?('kB') # Data transfer updates
      sleep 1.5  # Faster updates for data transfer
    elsif progress_data[:message].include?('tablespace')
      sleep 1
    elsif progress_data[:status] == 'active'
      sleep 3  # Final step gets more time
    else
      sleep 2  # Default timing
    end
    
  rescue => e
    puts "   ❌ Error: #{e.message}"
  end
end

puts "\n🎉 Progress simulation completed!"
puts "💡 The enhanced replica setup now provides detailed progress feedback:"
puts "   • pg_basebackup progress monitoring"
puts "   • Data transfer statistics (KB copied, percentages)"
puts "   • Tablespace processing status"
puts "   • PostgreSQL startup verification"
puts "   • Replication connection validation"
puts "   • Synchronization lag information"
puts ""
puts "🔍 Check the browser to see if all progress messages appeared"
puts "📊 This gives users much better visibility into replica creation progress!"
