#!/usr/bin/env ruby

# Test complete node destruction workflow with ActionCable

puts "🧪 Testing Node Destruction Workflow with ActionCable"
puts "=" * 60

# Find nodes to test
nodes = Node.includes(:cluster).limit(3)
if nodes.empty?
  puts "❌ No nodes found. Create some nodes first."
  exit 1
end

puts "📋 Available nodes for testing:"
nodes.each_with_index do |node, i|
  puts "  #{i + 1}. #{node.name} (ID: #{node.id}) - Status: #{node.status} - Cluster: #{node.cluster.name}"
end

print "\n🎯 Enter node number to test (1-#{nodes.count}): "
choice = gets.chomp.to_i

if choice < 1 || choice > nodes.count
  puts "❌ Invalid choice. Exiting."
  exit 1
end

test_node = nodes[choice - 1]
puts "\n🎯 Selected: #{test_node.name} (ID: #{test_node.id})"
puts "🌐 Cluster: #{test_node.cluster.name} (ID: #{test_node.cluster_id})"
puts "📊 Current status: #{test_node.status}"

puts "\n⚠️  This will ACTUALLY destroy the node infrastructure!"
print "💀 Are you sure you want to proceed? (type 'yes' to continue): "
confirmation = gets.chomp

if confirmation.downcase != 'yes'
  puts "❌ Cancelled. No changes made."
  exit 0
end

puts "\n🚀 Starting destruction process..."
puts "👀 Watch your browser for real-time status updates!"
puts ""

# Start the destruction process
puts "1️⃣ Calling node.deprovision!..."
test_node.deprovision!

puts "✅ Destruction job queued successfully!"
puts ""
puts "🔍 Expected ActionCable workflow:"
puts "   1. Status changes to 'destroying' → Buttons should be disabled"
puts "   2. Progress messages appear during destruction"
puts "   3. Status changes to 'destroyed' → Row/card should be removed"
puts "   4. Database record gets deleted"
puts ""
puts "📱 Check your browser on these pages:"
puts "   • Cluster show: /clusters/#{test_node.cluster_id}"
puts "   • Nodes index: /clusters/#{test_node.cluster_id}/nodes"
puts "   • Node show: /clusters/#{test_node.cluster_id}/nodes/#{test_node.id} (should redirect)"
puts ""
puts "🎯 Look for ActionCable messages in browser console:"
puts "   • '✅ Received node status update'"
puts "   • Status badge color changes"
puts "   • Button disabling"
puts "   • Element removal animations"
puts ""
puts "✨ Test complete! Monitor the browser for real-time updates."
