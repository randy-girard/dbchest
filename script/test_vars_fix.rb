#!/usr/bin/env ruby

node = Node.first
if node
  puts '=== Testing Updated vars_to_tfvars Method ==='
  
  # Generate cloud-init script and encode it
  cloud_init_service = CloudInitService.new
  script = cloud_init_service.generate_user_data(node.id)
  encoded = Base64.strict_encode64(script)
  
  # Test the updated vars_to_tfvars method
  terraform_service = TerraformCreateService.new
  vars = {
    name: 'test-node',
    cloud_init_user_data: encoded,
    ssh_public_key: 'ssh-rsa AAAAB3NzaC1yc2EAAAA test with "quotes"',
    ip_address: '192.168.1.100/24'
  }
  
  tfvars = terraform_service.send(:vars_to_tfvars, vars)
  
  puts "Generated tfvars length: #{tfvars.length} characters"
  puts
  
  # Check for proper handling
  lines = tfvars.split("\n")
  cloud_init_line = lines.find { |line| line.include?('cloud_init_user_data') }
  ssh_key_line = lines.find { |line| line.include?('ssh_public_key') }
  
  puts 'Validation:'
  puts "  Base64 cloud_init_user_data preserved (no double escapes): #{!cloud_init_line.include?('\\\\')}"
  puts "  SSH key quotes escaped: #{ssh_key_line.include?('\\"')}"
  puts "  Base64 pattern detected: #{encoded.match?(/\A[A-Za-z0-9+\/]*={0,2}\z/)}"
  
  puts
  puts "Sample lines:"
  puts "  Cloud-init: #{cloud_init_line[0..80]}..."
  puts "  SSH key: #{ssh_key_line}"
  
  puts
  puts '✅ Updated vars_to_tfvars test completed!'
else
  puts 'No nodes found for testing'
end
