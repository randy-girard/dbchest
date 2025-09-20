#!/usr/bin/env ruby

# Test replica node status updates via ActionCable

puts "🧪 Testing Replica Node ActionCable Updates"
puts "=" * 50

# Find a primary node with replicas
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

puts "\n📱 Open the primary node page in your browser:"
puts "   URL: /clusters/#{primary_node.cluster_id}/nodes/#{primary_node.id}"
puts "   👀 Watch the replicas table at the bottom of the page"
puts ""

puts "🔄 Testing replica status updates..."

# Test sequence
test_statuses = [
  { status: 'provisioning', message: 'Test: Provisioning replica...' },
  { status: 'configuring', message: 'Test: Configuring replica settings...' },
  { status: 'active', message: 'Test: Replica is now active' },
  { status: replica.status, message: 'Test: Restored original status' }
]

test_statuses.each_with_index do |test_data, index|
  puts "\n#{index + 1}. Updating replica '#{replica.name}' to '#{test_data[:status]}'..."
  
  begin
    replica.update_status!(test_data[:status], test_data[:message])
    puts "   ✅ Status updated to '#{test_data[:status]}'"
    puts "   📡 ActionCable should broadcast to:"
    puts "      • node_status_updates (general)"
    puts "      • node_status_#{replica.id} (replica-specific)" 
    puts "      • cluster_#{replica.cluster_id}_node_status (cluster-wide)"
    puts "   🎯 Look for replica status badge change in browser"
    
    sleep 3  # Give time to observe changes
  rescue => e
    puts "   ❌ Error: #{e.message}"
  end
end

puts "\n✨ Test complete!"
puts ""
puts "🔍 Expected behavior in browser:"
puts "   • Replica status badge should change colors"
puts "   • Status text should update (Provisioning → Configuring → Active)"
puts "   • Status messages should appear below the badge"
puts ""
puts "🐛 If updates aren't showing:"
puts "   1. Check browser console for ActionCable messages"
puts "   2. Verify '✅ Received node status update' appears"
puts "   3. Look for 'Found X status elements for node #{replica.id}'"
puts "   4. Make sure replica table has data-node-status attributes"
