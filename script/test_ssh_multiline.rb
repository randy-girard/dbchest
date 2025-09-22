#!/usr/bin/env ruby

puts '=== Testing SSH Key Multiline Issue ==='

# Get a node with SSH keys
node = Node.find(5)  # The one with "provisioning" status
if node && node.ssh_public_key.present?
  puts "Testing with Node #{node.id}: #{node.name}"
  puts "SSH public key length: #{node.ssh_public_key.length}"
  puts "SSH private key length: #{node.ssh_private_key.length}"
  
  # Test the vars_to_tfvars method with actual keys
  terraform_service = TerraformCreateService.new
  
  test_vars = {
    name: node.name,
    ssh_public_key: node.ssh_public_key,
    ssh_private_key: node.ssh_private_key,
    ip_address: "192.168.1.100/24"
  }
  
  puts "\n=== Testing vars_to_tfvars ==="
  tfvars = terraform_service.send(:vars_to_tfvars, test_vars)
  
  lines = tfvars.split("\n")
  puts "Generated #{lines.length} lines"
  
  lines.each_with_index do |line, idx|
    puts "Line #{idx + 1}: #{line[0..80]}#{line.length > 80 ? '...' : ''}"
  end
  
  # Check for problematic patterns
  puts "\n=== Analysis ==="
  pub_key_line = lines.find { |line| line.include?('ssh_public_key') }
  priv_key_line = lines.find { |line| line.include?('ssh_private_key') }
  
  if pub_key_line
    puts "Public key line length: #{pub_key_line.length}"
    puts "Public key has unescaped newlines: #{pub_key_line.count('\n') > 0}"
  end
  
  if priv_key_line
    puts "Private key line length: #{priv_key_line.length}"
    puts "Private key has unescaped newlines: #{priv_key_line.count('\n') > 0}"
    puts "Private key starts with: #{priv_key_line[0..50]}"
  end
  
else
  puts "Node 5 not found or no SSH keys"
end
