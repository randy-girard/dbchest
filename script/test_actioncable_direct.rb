# Simple ActionCable broadcast test
# Usage: Run this in Rails console to test if ActionCable is working

puts "=== ActionCable Broadcast Test ==="

# Test 1: Check if ActionCable server is running
puts "1. ActionCable server: #{ActionCable.server.class}"

# Test 2: Find a node to test with
node = Node.first
if node.nil?
  puts "❌ No nodes found. Create a node first."
  exit
end

puts "2. Testing with node: #{node.name} (ID: #{node.id})"

# Test 3: Direct broadcast to all streams
test_data = {
  id: node.id,
  status: 'active',
  status_display: 'TEST MESSAGE - Active',
  status_badge_class: 'bg-success',
  name: node.name,
  message: 'This is a test broadcast message',
  updated_at: Time.current.iso8601
}

puts "3. Broadcasting test message..."

# Broadcast to general stream
puts "   Broadcasting to: node_status_updates"
ActionCable.server.broadcast("node_status_updates", test_data)

# Broadcast to specific node stream  
puts "   Broadcasting to: node_status_#{node.id}"
ActionCable.server.broadcast("node_status_#{node.id}", test_data)

# Broadcast to cluster stream
puts "   Broadcasting to: cluster_#{node.cluster_id}_node_status"
ActionCable.server.broadcast("cluster_#{node.cluster_id}_node_status", test_data)

puts "✅ Test broadcasts sent!"
puts ""
puts "🔍 Check your browser console for received messages."
puts "💡 In browser console, run: debugActionCable()"
puts "🔧 To test the controller, run: application.getControllerForElementAndIdentifier(document.querySelector('[data-controller*=node-status]'), 'node-status').testConnection()"
