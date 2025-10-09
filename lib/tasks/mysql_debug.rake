namespace :mysql do
  desc "Debug MySQL user creation for a node"
  task :debug_user, [:node_id] => :environment do |t, args|
    node_id = args[:node_id] || ENV['NODE_ID']
    
    unless node_id
      puts "Usage: rake mysql:debug_user[NODE_ID]"
      puts "   or: NODE_ID=123 rake mysql:debug_user"
      exit 1
    end
    
    node = Node.find_by(id: node_id)
    unless node
      puts "Node #{node_id} not found"
      exit 1
    end
    
    puts "=" * 80
    puts "MySQL User Debug for Node #{node.id} (#{node.name})"
    puts "=" * 80
    puts "Status: #{node.status}"
    puts "Database Type: #{node.database_type_slug}"
    puts "Database Version: #{node.database_version}"
    puts "IP Address: #{node.get_ip_address}"
    puts "Primary: #{node.primary?}"
    puts ""
    
    puts "Credentials:"
    node.credentials.each do |cred|
      puts "  - #{cred.username} (ID: #{cred.id})"
    end
    puts ""
    
    puts "Checking MySQL users on node..."
    puts "-" * 80
    
    service = AnsibleRunService.new
    result = service.perform(node.id, "list_users.yml", vars: {
      mysql_root_password: node.root_password
    })
    
    puts ""
    puts "Check the Ansible log at: log/ansible/node_#{node.id}_list_users.yml.log"
    puts ""
    
    puts "To manually create the default user, run:"
    puts "  rake mysql:create_default_user[#{node.id}]"
  end
  
  desc "Manually create default user for a MySQL node"
  task :create_default_user, [:node_id] => :environment do |t, args|
    node_id = args[:node_id] || ENV['NODE_ID']
    
    unless node_id
      puts "Usage: rake mysql:create_default_user[NODE_ID]"
      puts "   or: NODE_ID=123 rake mysql:create_default_user"
      exit 1
    end
    
    node = Node.find_by(id: node_id)
    unless node
      puts "Node #{node_id} not found"
      exit 1
    end
    
    puts "Creating default user for node #{node.id} (#{node.name})..."
    
    # Find or create the default credential
    credential = node.credentials.find { |c| c.username == "default" }
    
    if credential
      puts "Default credential already exists (ID: #{credential.id})"
      puts "Username: #{credential.username}"
      puts "Password: #{credential.password}"
    else
      puts "Creating new default credential..."
      password = SecureRandom.alphanumeric(32)
      credential = node.credentials.create!(
        username: "default",
        password: password
      )
      puts "Created credential (ID: #{credential.id})"
      puts "Username: #{credential.username}"
      puts "Password: #{credential.password}"
    end
    
    puts ""
    puts "Provisioning user on MySQL node..."
    
    deployment_service = node.deployment_service
    begin
      deployment_service.create_user!(
        credential.username,
        credential.password,
        "*.*:ALL"
      )
      puts "✓ User created successfully!"
      puts ""
      puts "Connection string:"
      puts "  mysql -h #{node.get_ip_address} -P 3306 -u #{credential.username} -p#{credential.password}"
      puts ""
      puts "Check the Ansible log at: log/ansible/node_#{node.id}_create_user.yml.log"
    rescue => e
      puts "✗ Error creating user: #{e.message}"
      puts e.backtrace.first(5).join("\n")
    end
  end
  
  desc "Test MySQL connection from DBChest server"
  task :test_connection, [:node_id] => :environment do |t, args|
    node_id = args[:node_id] || ENV['NODE_ID']
    
    unless node_id
      puts "Usage: rake mysql:test_connection[NODE_ID]"
      exit 1
    end
    
    node = Node.find_by(id: node_id)
    unless node
      puts "Node #{node_id} not found"
      exit 1
    end
    
    credential = node.credentials.find { |c| c.username == "default" }
    unless credential
      puts "No default credential found for node #{node.id}"
      puts "Run: rake mysql:create_default_user[#{node.id}]"
      exit 1
    end
    
    ip = node.get_ip_address
    username = credential.username
    password = credential.password
    
    puts "Testing MySQL connection..."
    puts "Host: #{ip}"
    puts "User: #{username}"
    puts ""
    
    cmd = "mysql -h #{ip} -P 3306 -u #{username} -p#{password} -e 'SELECT 1 AS test;' 2>&1"
    output = `#{cmd}`
    
    if $?.success?
      puts "✓ Connection successful!"
      puts output
    else
      puts "✗ Connection failed!"
      puts output
      puts ""
      puts "Try connecting manually:"
      puts "  mysql -h #{ip} -P 3306 -u #{username} -p#{password}"
    end
  end
end

