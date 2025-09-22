#!/usr/bin/env ruby
# Test script to verify terraform vars generation with cloud-init

puts "=== Terraform Vars Generation Test ==="
puts "Time: #{Time.current}"

# Test with a sample node
node = Node.first

if node.nil?
  puts "❌ No nodes found. Please create a node first."
  exit 1
end

puts "✅ Testing with node: #{node.name} (ID: #{node.id})"

begin
  # Generate cloud-init script
  cloud_init_script = CloudInitService.new.generate_user_data(node.id, false)
  puts "✅ Generated cloud-init script (#{cloud_init_script.length} chars)"
  
  # Encode with base64
  encoded_script = Base64.strict_encode64(cloud_init_script)
  puts "✅ Base64 encoded script (#{encoded_script.length} chars)"
  
  # Test vars generation
  test_vars = {
    name: "test-node",
    cloud_init_user_data: encoded_script,
    ssh_public_key: "ssh-rsa AAAAB3NzaC1yc2EAAAA test",
    ip_address: "192.168.1.100/24"
  }
  
  # Create a test service to access the private method
  require './app/services/terraform_common.rb'
  class TestTerraformService
    include TerraformCommon
    
    def test_vars_generation(vars)
      vars_to_tfvars(vars)
    end
  end
  
  service = TestTerraformService.new
  tfvars_content = service.test_vars_generation(test_vars)
  
  puts "✅ Generated tfvars content:"
  puts "--- TFVARS CONTENT ---"
  puts tfvars_content
  puts "--- END TFVARS ---"
  
  # Check for potential issues
  issues = []
  issues << "Contains unescaped quotes" if tfvars_content.match?(/[^\\]"/)
  issues << "Contains newlines in values" if tfvars_content.lines.any? { |line| line.include?("\n") && !line.strip.empty? }
  
  if issues.empty?
    puts "✅ No obvious formatting issues detected"
  else
    puts "⚠️  Potential issues: #{issues.join(', ')}"
  end
  
rescue => e
  puts "❌ Error during test: #{e.message}"
  puts e.backtrace.first(3)
end

puts "\n🎉 Test completed!"
