# test_script.rb
require "capybara"
require "capybara/dsl"
require "faker"

# Include Capybara DSL into this script
include Capybara::DSL

def wait_until(&blk)
  while true
    if blk.call
      return true
    end
    sleep 5
  end
end

# Configure Capybara
Capybara.default_driver = :selenium_chrome # or :selenium_chrome_headless
Capybara.app_host = "http://localhost:5000" # adjust to your app

# Visit your app
visit "/"

puts "Page title: #{title}"

#click_link "Providers"
#click_link "New Provider"
#fill_in "Name", with: "Proxmox"
#select "Proxmox", from: "Provider Type"
#fill_in "Api url", "https://10.0.0.200:8006/api2/json"
#fill_in "Username", "terraform-prov@pve"
#fill_in "Password", "rg_20060410!"

# Example interaction
#fill_in "username", with: "test_user"
#fill_in "password", with: "secret"
click_link "Clusters"
click_link "New Cluster"

fill_in "cluster_name", with: "postgres-#{Faker::Internet.slug}"
select "PostgreSQL", from: "Database Type"
click_button "Create Cluster"

@node_name = "postgres-node-#{Faker::Internet.slug}"
click_link "Add first node"
select "Proxmox", from: "Infrastructure Provider"
fill_in "Node Name", with: @node_name
select "PostgreSQL 12", from: "Database Version"
select "pve", from: "node_node"
sleep 1.5
select "vmdisks", from: "node_storage"
select "local", from: "template_storage"
sleep 1.5
select "local:vztmpl/debian-10-turnkey-observium_16.1-1_amd64.tar.gz", from: "template_template"

fill_in "node_disk_size", with: "10"
fill_in "node_ip_address", with: "10.0.0.250/32"
fill_in "node_gateway", with: "10.0.0.1"
click_button "Create Node"

wait_until {
  Node.where(name: @node_name).first&.active?
}

click_button "Delete node"

wait_until {
  Node.where(name: @node_name).first == nil
}

click_button "Delete cluster"

#click_link "Providers"
#click_link "All Providers"


puts "Current URL: #{current_url}"
puts "Page body includes 'Welcome'? #{page.has_content?("Welcome")}"

# Clean up
Capybara.reset_sessions!
Capybara.current_session.driver.quit
