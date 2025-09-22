#!/usr/bin/env ruby
# Test script to verify cloud-init integration

puts "=== Cloud-Init Integration Test ==="
puts "Time: #{Time.current}"

# Test 1: Check if we can generate cloud-init user data
puts "\n--- Test 1: Generate Cloud-Init User Data ---"
begin
  # Find a node to test with
  node = Node.first
  if node.nil?
    puts "❌ No nodes found. Skipping cloud-init generation test."
  else
    puts "✅ Testing with node: #{node.name} (ID: #{node.id})"
    
    # Test primary node script generation
    primary_script = CloudInitService.new.generate_user_data(node.id, false)
    puts "✅ Primary node script generated (#{primary_script.length} characters)"
    
    # Test replica node script generation with an existing replica
    replica = Node.where.not(parent_node_id: nil).first
    if replica
      replica_script = CloudInitService.new.generate_user_data(replica.id, true)
      puts "✅ Replica node script generated (#{replica_script.length} characters)"
    else
      puts "⚠️  No existing replica node found - skipping replica script test"
      puts "  💡 Create a replica node through the web interface to test this functionality"
    end
    
    puts "\n📄 Sample of primary script:"
    puts primary_script[0..300] + "..."
  end
rescue => e
  puts "❌ Cloud-init generation failed: #{e.message}"
end

# Test 2: Check callback URL generation
puts "\n--- Test 2: Callback URL Generation ---"
begin
  if defined?(Rails) && Rails.application
    node_id = 1
    callback_url = Rails.application.routes.url_helpers.node_status_callback_url(
      node_id, 
      host: 'localhost:3000'
    )
    puts "✅ Callback URL: #{callback_url}"
  else
    puts "❌ Rails routes not available"
  end
rescue => e
  puts "❌ Callback URL generation failed: #{e.message}"
end

# Test 3: Check if services can be instantiated
puts "\n--- Test 3: Service Instantiation ---"
services_to_test = [
  'CloudInitService',
  'ReplicaConfigurationService'
]

services_to_test.each do |service_name|
  begin
    service_class = Object.const_get(service_name)
    instance = service_class.new
    puts "✅ #{service_name} - instantiated successfully"
  rescue => e
    puts "❌ #{service_name} - failed: #{e.message}"
  end
end

# Test 4: Check if job classes exist
puts "\n--- Test 4: Job Class Availability ---"
job_classes = [
  'CreateService'
]

job_classes.each do |job_name|
  begin
    job_class = Object.const_get(job_name)
    puts "✅ #{job_name} - class available"
    
    # Check if it includes Sidekiq::Job
    if job_class.included_modules.any? { |mod| mod.to_s.include?('Sidekiq') }
      puts "  ✅ Includes Sidekiq functionality"
    else
      puts "  ⚠️  May not be a proper Sidekiq job"
    end
  rescue => e
    puts "❌ #{job_name} - not available: #{e.message}"
  end
end

# Test 5: Check controller availability
puts "\n--- Test 5: Controller Availability ---"
begin
  controller_class = NodeStatusCallbacksController
  puts "✅ NodeStatusCallbacksController - available"
  
  # Check if it has the required action
  if controller_class.instance_methods(false).include?(:update)
    puts "  ✅ Has update action"
  else
    puts "  ❌ Missing update action"
  end
rescue => e
  puts "❌ NodeStatusCallbacksController - not available: #{e.message}"
end

puts "\n🎉 Test completed!"
puts "🔧 If any tests failed, check the respective files for syntax errors."
puts "🌐 Make sure the Rails server is running for full functionality testing."
