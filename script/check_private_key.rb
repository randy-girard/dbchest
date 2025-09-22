#!/usr/bin/env ruby

node = Node.find(5)
terraform_service = TerraformCreateService.new

# Test just the private key processing
test_vars = { ssh_private_key: node.ssh_private_key }
tfvars = terraform_service.send(:vars_to_tfvars, test_vars)

puts 'Private key tfvars line (first 200 chars):'
puts tfvars[0..199]
puts
puts 'Private key tfvars line (last 100 chars):'
puts tfvars[-100..-1]

puts "\nChecking for actual formatting issues:"
puts "Line contains literal newline characters: #{tfvars.include?("\n") && !tfvars.gsub("\\n", "").include?("\n")}"
puts "Line starts and ends with quotes properly: #{tfvars.start_with?('ssh_private_key = "') && tfvars.end_with?('"')}"

# Count escaped vs unescaped sequences
escaped_newlines = tfvars.scan(/\\n/).length
literal_newlines = tfvars.count("\n")
puts "Escaped newlines (\\n): #{escaped_newlines}"
puts "Literal newlines: #{literal_newlines}"

# This should be valid Terraform if it's all on one line with proper escapes
puts "\nTerraform validity check:"
puts "✅ Single line format: #{literal_newlines == 0}"
puts "✅ Proper quotes: #{tfvars.start_with?('ssh_private_key = "') && tfvars.end_with?('"')}"
