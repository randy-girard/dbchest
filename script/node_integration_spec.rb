# DBChest Node Integration Test Script
# This script tests end-to-end node provisioning for all database types
# against a live development server using Capybara

require "capybara"
require "capybara/dsl"
require "faker"

# Include Capybara DSL into this script
include Capybara::DSL

# ============================================================================
# Configuration
# ============================================================================

# Configure Capybara
Capybara.default_driver = :selenium_chrome # or :selenium_chrome_headless
Capybara.app_host = "http://localhost:5000" # adjust to your app

# Provider configuration (adjust for your environment)
PROVIDER_CONFIG = {
  name: "Proxmox",
  node_field: "pve",
  storage_field: "vmdisks",
  template_storage_field: "local",
  template_field: "local:vztmpl/debian-10-turnkey-observium_16.1-1_amd64.tar.gz"
}

random_ip_part = 210 + rand(30).to_i
# Network configuration for test nodes
NETWORK_CONFIG = {
  disk_size: "10",
  ip_address: "10.0.0.#{random_ip_part}/32",
  gateway: "10.0.0.1"
}

REPLICA_NETWORK_CONFIG = {
  disk_size: "10",
  ip_address: "10.0.0.#{random_ip_part + 1}/32",
  gateway: "10.0.0.1"
}

# ============================================================================
# Database Type Test Configurations
# ============================================================================

DATABASE_TEST_CONFIGS = {
  postgresql: {
    name: "PostgreSQL",
    versions: [12],#, 13, 14, 15, 16, 17],
    cluster_prefix: "postgres",
    node_prefix: "postgres-node",
    enabled: true
  },
  mysql: {
    name: "MySQL",
    versions: ["5.7", "8.0"],
    cluster_prefix: "mysql",
    node_prefix: "mysql-node",
    enabled: false # Enable when MySQL support is ready
  },
  mongodb: {
    name: "MongoDB",
    versions: ["4.4", "5.0", "6.0"],
    cluster_prefix: "mongodb",
    node_prefix: "mongodb-node",
    enabled: false # Enable when MongoDB support is ready
  },
  cassandra: {
    name: "Cassandra",
    versions: ["3.11", "4.0"],
    cluster_prefix: "cassandra",
    node_prefix: "cassandra-node",
    enabled: false # Enable when Cassandra support is ready
  },
  redis: {
    name: "Redis",
    versions: ["6.2", "7.0"],
    cluster_prefix: "redis",
    node_prefix: "redis-node",
    enabled: false # Enable when Redis support is ready
  }
}

# ============================================================================
# Helper Methods
# ============================================================================

def wait_until(timeout: 600, interval: 5, &blk)
  start_time = Time.now
  while true
    return true if yield

    if Time.now - start_time > timeout
      puts "⏱️  Timeout after #{timeout} seconds"
      return false
    end

    sleep interval
  end
end

def create_cluster(database_type_name, cluster_name)
  puts "  📦 Creating cluster: #{cluster_name}"

  click_link "Clusters"
  first(:link, "New Cluster").click

  fill_in "cluster_name", with: cluster_name
  select database_type_name, from: "Database Type"
  click_button "Create Cluster"

  puts "  ✅ Cluster created"
end

def provision_node(node_name, database_version)
  puts "  🚀 Provisioning node: #{node_name} (version: #{database_version})"

  click_link "Add first node"
  select PROVIDER_CONFIG[:name], from: "Infrastructure Provider"
  fill_in "Node Name", with: node_name
  select "#{database_version}", from: "Database Version", match: :first

  # Provider-specific fields
  select PROVIDER_CONFIG[:node_field], from: "node_node"
  sleep 1.5
  select PROVIDER_CONFIG[:storage_field], from: "node_storage"
  select PROVIDER_CONFIG[:template_storage_field], from: "template_storage"
  sleep 1.5
  select PROVIDER_CONFIG[:template_field], from: "template_template"

  # Network configuration
  fill_in "node_disk_size", with: NETWORK_CONFIG[:disk_size]
  fill_in "node_ip_address", with: NETWORK_CONFIG[:ip_address]
  fill_in "node_gateway", with: NETWORK_CONFIG[:gateway]

  click_button "Create Node"

  puts "  ⏳ Waiting for node to provision..."
end

def provision_node_replica(node_name)
  puts "  🚀 Provisioning node replica: #{node_name}"

  page.refresh

  click_link "Add first replica"
  fill_in "Replica Name", with: node_name

  sleep 1.5

  # Network configuration
  fill_in "node_ip_address", with: REPLICA_NETWORK_CONFIG[:ip_address]
  fill_in "node_gateway", with: REPLICA_NETWORK_CONFIG[:gateway]

  click_button "Create Replica"

  puts "  ⏳ Waiting for node replica to provision..."
end

def wait_for_node_status
  result = ""

  success = wait_until(timeout: 600) do
    if page.has_text?(/\bActive\b/, wait: 0)
      result = "Active"
      true
    elsif page.has_text?(/\bError(ed)?\b/, wait: 0)
      result = "Error"
      true
    else
      false
    end
  end

  result = "Timeout" unless success
  result
end

def cleanup_node(node_name)
  puts "  🗑️  Deleting node: #{node_name}"

  within(:xpath, "//tr[td[contains(., '#{node_name}')]]") do
    find("button.dropdown-toggle").click
  end

  click_button "Delete"

  wait_until do
    !page.has_text?(node_name)
  end

  puts "  ✅ Node deleted"
end

def cleanup_node_replica(node_name)
  puts "  🗑️  Deleting node replica: #{node_name}"

  within(:xpath, "//div[@class='dropdown']") do
    find("button.dropdown-toggle").click
  end

  click_button "Delete Node"

  wait_until do
    !page.has_text?(node_name)
  end

  puts "  ✅ Node deleted"
end

def cleanup_cluster
  puts "  🗑️  Deleting cluster"

  within(:xpath, "//div.dropdown") do
    find("button.dropdown-toggle").click
  end

  click_button "Delete Cluster"

  puts "  ✅ Cluster deleted"
end

def fetch_cloud_init_logs(node_name)
  puts "  📋 Fetching cloud-init logs from failed node..."

  begin
    # Try to find the node ID from the page
    # The node show page should have data attributes with the node ID
    node_id_element = page.find('[data-node-status-node-id-value]', visible: false)
    node_id = node_id_element['data-node-status-node-id-value']

    if node_id.blank?
      puts "  ⚠️  Could not find node ID on page"
      return nil
    end

    # Fetch node details via API
    require 'net/http'
    require 'json'
    require 'net/ssh'
    require 'tempfile'

    uri = URI("#{Capybara.app_host}/nodes/#{node_id}/status.json")
    response = Net::HTTP.get_response(uri)

    unless response.is_a?(Net::HTTPSuccess)
      puts "  ⚠️  Could not fetch node details from API"
      return nil
    end

    node_data = JSON.parse(response.body)

    # We need to get the IP address and SSH key from the database
    # Since we're in a script, we can connect to Rails
    require File.expand_path('../../config/environment', __FILE__)

    node = Node.find(node_id)
    ip_address = node.get_ip_address

    if ip_address.blank?
      puts "  ⚠️  Node has no IP address"
      return nil
    end

    puts "  🔌 Connecting to #{ip_address}..."

    # Create temporary file for SSH key
    key_file = Tempfile.new(['ssh_key', '.pem'])
    key_file.write(node.ssh_private_key)
    key_file.chmod(0600)
    key_file.flush
    key_file.close

    # Fetch the log file via SSH
    log_content = nil
    Net::SSH.start(ip_address, 'root',
                   keys: [key_file.path],
                   timeout: 10,
                   non_interactive: true,
                   verify_host_key: :never) do |ssh|

      # Check if log file exists
      result = ssh.exec!("test -f /var/log/dbchest-setup.log && echo 'exists' || echo 'missing'")

      if result.strip == 'missing'
        puts "  ⚠️  Log file not found on node"
        return nil
      end

      # Fetch the log file
      log_content = ssh.exec!("cat /var/log/dbchest-setup.log")
      puts "  ✅ Retrieved #{log_content.lines.count} lines of logs"
    end

    key_file.unlink
    log_content

  rescue Net::SSH::AuthenticationFailed => e
    puts "  ❌ SSH authentication failed: #{e.message}"
    nil
  rescue Errno::ETIMEDOUT, Errno::ECONNREFUSED, Net::SSH::ConnectionTimeout => e
    puts "  ❌ Could not connect to node: #{e.message}"
    nil
  rescue => e
    puts "  ❌ Error fetching logs: #{e.message}"
    puts "  #{e.backtrace.first(3).join("\n  ")}"
    nil
  end
end

def parse_error_from_logs(log_content)
  return nil if log_content.blank?

  errors = []

  # Look for ERROR lines
  log_content.each_line do |line|
    if line.include?('ERROR:') || line.include?('FAILED') || line.include?('error')
      errors << line.strip
    end
  end

  # Return last 10 error lines
  errors.last(10).join("\n")
end


# ============================================================================
# Main Test Execution
# ============================================================================

puts "=" * 80
puts "DBChest Node Integration Tests"
puts "=" * 80
puts ""

# Visit the app to ensure it's running
visit "/"
puts "✅ Connected to #{Capybara.app_host}"
puts "📄 Page title: #{title}"
puts ""

# Collect all test results
all_results = []

# Run tests for each enabled database type
DATABASE_TEST_CONFIGS.each do |db_slug, config|
  next unless config[:enabled]

  puts "=" * 80
  puts "Testing #{config[:name]}"
  puts "=" * 80
  puts ""

  config[:versions].each do |version|
    puts "-" * 80
    puts "Testing #{config[:name]} #{version}"
    puts "-" * 80

    cluster_name = "#{config[:cluster_prefix]}-#{Faker::Internet.slug}"
    node_name = "#{config[:node_prefix]}-#{Faker::Internet.slug}"

    begin
      # Create cluster
      visit "/"
      create_cluster(config[:name], cluster_name)

      # Provision node
      provision_node(node_name, version)

      # Wait for result
      result = wait_for_node_status

      # If node failed, try to fetch logs
      error_logs = nil
      error_summary = nil
      if result == "Error" || result == "Timeout"
        error_logs = fetch_cloud_init_logs(node_name)
        if error_logs
          error_summary = parse_error_from_logs(error_logs)
          if error_summary.present?
            puts "  📋 Error details from cloud-init logs:"
            puts "  " + ("-" * 76)
            error_summary.lines.each do |line|
              puts "  #{line}"
            end
            puts "  " + ("-" * 76)
          end
        end
      end

      # Record result
      test_result = {
        database_type: config[:name],
        version: version,
        cluster_name: cluster_name,
        node_name: node_name,
        status: result,
        timestamp: Time.now
      }

      # Add error details if available
      if error_summary.present?
        test_result[:error_summary] = error_summary
        test_result[:full_logs] = error_logs if error_logs.present?
      end

      all_results << test_result

      # Print result
      status_emoji = result == "Active" ? "✅" : "❌"
      puts "  #{status_emoji} Primary Result: #{result}"
      puts ""

      replica_node_name = "#{node_name}-replica"
      provision_node_replica(replica_node_name)

      result = wait_for_node_status

      # If node failed, try to fetch logs
      error_logs = nil
      error_summary = nil
      if result == "Error" || result == "Timeout"
        error_logs = fetch_cloud_init_logs(node_name)
        if error_logs
          error_summary = parse_error_from_logs(error_logs)
          if error_summary.present?
            puts "  📋 Error details from cloud-init logs:"
            puts "  " + ("-" * 76)
            error_summary.lines.each do |line|
              puts "  #{line}"
            end
            puts "  " + ("-" * 76)
          end
        end
      end

      # Record result
      test_result = {
        database_type: config[:name],
        version: version,
        cluster_name: cluster_name,
        node_name: node_name,
        status: result,
        timestamp: Time.now
      }

      # Add error details if available
      if error_summary.present?
        test_result[:error_summary] = error_summary
        test_result[:full_logs] = error_logs if error_logs.present?
      end

      all_results << test_result

      # Print result
      status_emoji = result == "Active" ? "✅" : "❌"
      puts "  #{status_emoji} Replica Result: #{result}"
      puts ""

      # Cleanup
      cleanup_node_replica(replica_node_name)
      cleanup_node(node_name)
      cleanup_cluster

    rescue => e
      puts "  ❌ Error: #{e.message}"
      puts "  #{e.backtrace.first(5).join("\n  ")}"

      all_results << {
        database_type: config[:name],
        version: version,
        cluster_name: cluster_name,
        node_name: node_name,
        status: "Exception",
        error: e.message,
        timestamp: Time.now
      }
    end

    puts ""
  end

  puts ""
end

# ============================================================================
# Print Summary Report
# ============================================================================

puts "=" * 80
puts "Test Summary"
puts "=" * 80
puts ""

# Group results by database type
results_by_type = all_results.group_by { |r| r[:database_type] }

results_by_type.each do |db_type, results|
  puts "#{db_type}:"
  results.each do |result|
    status_emoji = result[:status] == "Active" ? "✅" : "❌"
    puts "  #{status_emoji} Version #{result[:version]}: #{result[:status]}"
  end
  puts ""
end

# Overall statistics
total_tests = all_results.count
successful_tests = all_results.count { |r| r[:status] == "Active" }
failed_tests = total_tests - successful_tests
success_rate = total_tests > 0 ? (successful_tests.to_f / total_tests * 100).round(2) : 0

puts "-" * 80
puts "Total Tests: #{total_tests}"
puts "Successful: #{successful_tests}"
puts "Failed: #{failed_tests}"
puts "Success Rate: #{success_rate}%"
puts "=" * 80

# Export results to JSON file
require "json"
results_file = "integration_test_results_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
File.write(results_file, JSON.pretty_generate({
  summary: {
    total: total_tests,
    successful: successful_tests,
    failed: failed_tests,
    success_rate: success_rate
  },
  results: all_results
}))

puts ""
puts "📊 Detailed results saved to: #{results_file}"
puts ""

# Clean up
Capybara.reset_sessions!
Capybara.current_session.driver.quit

puts "✅ Integration tests complete!"
