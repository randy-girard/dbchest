#!/usr/bin/env ruby
# This script can be used to test ActionCable broadcasts
# Usage: bin/rails runner script/test_node_status_broadcast.rb

puts "=== ActionCable Node Status Broadcast Test ==="
puts "Time: #{Time.current}"

# Find the first node or create one for testing
node = Node.first

if node.nil?
  puts "❌ No nodes found. Please create a node first through the web interface."
  exit 1
end

puts "✅ Testing ActionCable broadcasts for node: #{node.name} (ID: #{node.id})"
puts "📡 Current ActionCable server: #{ActionCable.server.inspect}"

# Test single broadcast first
puts "\n--- Single Broadcast Test ---"
puts "📤 Broadcasting test message..."
node.update_status!('provisioning', 'TEST: ActionCable broadcast test message')
puts "✅ Single broadcast sent"

# Wait for user confirmation
puts "\n🔍 Check your browser console and page for the update."
puts "Press Enter to continue with full test, or Ctrl+C to stop..."
STDIN.gets

# Simulate different status changes
puts "\n--- Full Status Sequence Test ---"
statuses = [
  ['provisioning', 'Starting infrastructure provisioning...'],
  ['configuring', 'Installing and configuring PostgreSQL...'],
  ['active', 'Node is now active and ready'],
  ['error', 'An error occurred during provisioning'],
  ['destroying', 'Starting node destruction...'],
  ['active', 'Test completed - node is active']
]

statuses.each_with_index do |(status, message), index|
  puts "📤 #{index + 1}/#{statuses.length} Broadcasting status: #{status} - #{message}"
  
  begin
    node.update_status!(status, message)
    puts "   ✅ Broadcast successful"
  rescue => e
    puts "   ❌ Broadcast failed: #{e.message}"
  end
  
  # Wait between status changes
  puts "   ⏳ Waiting 3 seconds..."
  sleep 3
end

puts "\n🎉 Test completed. Check your browser for real-time updates!"
puts "🔧 If updates didn't appear, check:"
puts "   - Browser console for JavaScript errors"
puts "   - Rails logs for ActionCable messages"
puts "   - Network tab for WebSocket connection"
