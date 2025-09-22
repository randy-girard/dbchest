#!/usr/bin/env ruby
# Script to check if DBChest setup is running on a node

puts "=== DBChest Node Status Checker ==="

node = Node.where(status: ['provisioning', 'configuring']).first
if node
  puts "Checking node: #{node.name} (ID: #{node.id}) - Status: #{node.status}"
  
  # Try to SSH to the node to check script status
  if node.ssh_private_key.present? && node.get_ip_address.present?
    ip = node.get_ip_address.split('/').first
    puts "Node IP: #{ip}"
    
    # Create a temporary SSH key file
    require 'tempfile'
    key_file = Tempfile.new('ssh_key')
    key_file.write(node.ssh_private_key)
    key_file.close
    File.chmod(0600, key_file.path)
    
    puts "\n=== Checking if DBChest script exists ==="
    system("ssh -i #{key_file.path} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@#{ip} 'ls -la /tmp/dbchest_setup.sh' 2>/dev/null")
    
    puts "\n=== Checking if DBChest script process is running ==="
    system("ssh -i #{key_file.path} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@#{ip} 'ps aux | grep -E \"dbchest_(setup|wrapper).sh\" | grep -v grep' 2>/dev/null")
    
    puts "\n=== Checking for wrapper script ==="
    system("ssh -i #{key_file.path} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@#{ip} 'ls -la /tmp/dbchest_*.sh 2>/dev/null || echo \"No DBChest scripts found in /tmp\"'")
    
    puts "\n=== Checking DBChest setup log (last 20 lines) ==="
    system("ssh -i #{key_file.path} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@#{ip} 'tail -20 /var/log/dbchest-setup.log 2>/dev/null || echo \"Log file not found\"'")
    
    puts "\n=== Checking PostgreSQL status ==="
    system("ssh -i #{key_file.path} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@#{ip} 'systemctl status postgresql --no-pager -l' 2>/dev/null")
    
    key_file.unlink
  else
    puts "❌ Node missing SSH key or IP address"
  end
else
  puts "No nodes found in provisioning or configuring status"
  puts "\nAll nodes:"
  Node.all.each do |n|
    puts "  #{n.name}: #{n.status}"
  end
end
