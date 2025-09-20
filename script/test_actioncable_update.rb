#!/usr/bin/env ruby

# Test ActionCable node status updates manually

# Find a node to test with
node = Node.first
if node.nil?
  puts "❌ No nodes found. Create a node first."
  exit 1
end

puts "🧪 Testing ActionCable with Node #{node.id} (#{node.name})"
puts "📋 Current status: #{node.status}"
puts "🌐 Cluster: #{node.cluster.name} (ID: #{node.cluster_id})"

# Test updating status to see if ActionCable broadcasts work
original_status = node.status

puts "\n🔄 Testing status update cycle..."

# Test sequence of status updates
test_statuses = ['provisioning', 'configuring', 'active', original_status]

test_statuses.each_with_index do |test_status, index|
  puts "\n#{index + 1}. Updating to '#{test_status}'..."
  
  begin
    node.update_status!(test_status, "Test message #{index + 1}: Status changed to #{test_status}")
    puts "   ✅ Status updated successfully"
    puts "   📡 ActionCable broadcast should have been sent"
    sleep 2  # Give time for broadcast to be received
  rescue => e
    puts "   ❌ Error: #{e.message}"
  end
end

puts "\n✨ Test complete! Check browser console for ActionCable messages."
puts "🔍 Look for messages like: '✅ Received node status update'"
