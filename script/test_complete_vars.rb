#!/usr/bin/env ruby

puts '=== Testing Complete Terraform Vars Generation ==='

node = Node.find(5)
if node
  # Simulate the full vars generation process like TerraformCreateService does
  terraform_service = TerraformCreateService.new
  
  # Generate cloud-init script and encode it
  cloud_init_service = CloudInitService.new
  is_replica = node.replica?
  cloud_init_script = cloud_init_service.generate_user_data(node.id, is_replica)
  encoded_script = Base64.strict_encode64(cloud_init_script)
  
  # Build the full vars hash like in TerraformCreateService
  vars = {}
  vars[:ssh_public_key] = node.ssh_public_key
  vars[:ssh_private_key] = node.ssh_private_key
  vars[:name] = node.name.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-+|-+$/, "")
  vars[:cloud_init_user_data] = encoded_script
  
  # Add node settings
  node.node_settings.each do |setting|
    vars[setting.key] = setting.value
  end
  
  # Add some test vars
  vars[:ip_address] = "192.168.1.100/24"
  vars[:api_url] = "https://proxmox.example.com:8006/api2/json"
  
  puts "Vars hash contains #{vars.keys.length} variables"
  puts "Variables: #{vars.keys.join(', ')}"
  
  # Generate tfvars content
  tfvars_content = terraform_service.send(:vars_to_tfvars, vars)
  lines = tfvars_content.split("\n")
  
  puts "\n=== Generated tfvars ==="
  puts "Total lines: #{lines.length}"
  puts "Total characters: #{tfvars_content.length}"
  
  # Check for potential issues
  issues = []
  issues << "Contains unescaped newlines" if tfvars_content.match(/[^\\]\n/)
  issues << "Contains unescaped quotes" if tfvars_content.match(/[^\\]"/)
  issues << "Contains incomplete lines" if lines.any? { |line| !line.include?('=') }
  
  puts "\n=== Issue Check ==="
  if issues.empty?
    puts "✅ No formatting issues detected!"
    puts "✅ Should work with Terraform"
  else
    puts "❌ Issues found:"
    issues.each { |issue| puts "  - #{issue}" }
  end
  
  # Show sample of key lines
  puts "\n=== Sample Lines ==="
  lines.each_with_index do |line, idx|
    if line.length > 100
      puts "Line #{idx + 1}: #{line[0..70]}...#{line[-20..-1]} (#{line.length} chars)"
    else
      puts "Line #{idx + 1}: #{line}"
    end
  end
  
else
  puts "Node 5 not found"
end
