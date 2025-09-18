class CreateService
  include Sidekiq::Job

  def initialize
  end

  def perform(node_id, is_replica = false)
    @node = Node.find_by_id(node_id)
    if @node
      TerraformCreateService.new.perform(@node.id)

      if is_replica && @node.replica?
        # Get primary node and ensure replication password exists
        primary_node = @node.parent_node
        replication_password = primary_node.ensure_replication_password!
        
        # Install PostgreSQL on the replica node (already replica-ready)
        # Since Ansible can connect, we know the IP address is working
        AnsibleRunService.new.perform(@node.id, "create_node.yml")
        
        # Now get IP addresses after Ansible has successfully connected
        # This proves the IPs are accessible
        @node.reload  # Ensure we have the latest data
        primary_ip = primary_node.get_ip_address
        replica_ip = @node.get_ip_address
        
        Rails.logger.info "Replication setup - Primary IP: #{primary_ip}, Replica IP: #{replica_ip}"
        
        # Validate we have IP addresses (they should be available since Ansible connected)
        if primary_ip.blank?
          raise "Cannot configure replication: Primary node #{primary_node.id} has no IP address"
        end
        
        if replica_ip.blank?
          # This shouldn't happen if Ansible connected successfully
          Rails.logger.error "Replica node #{@node.id} runtime_config: #{@node.runtime_config.inspect}"
          raise "Cannot configure replication: Replica node #{@node.id} has no IP address, but Ansible connected successfully"
        end
        
        Rails.logger.info "Configuring replication: Primary IP=#{primary_ip}, Replica IP=#{replica_ip}"
        
        # Add replica-specific configuration to primary node (replication user & pg_hba.conf entries)
        AnsibleRunService.new.perform(primary_node.id, "configure_primary_replication.yml", 
          vars: { 
            replica_ip: replica_ip,
            replica_node_name: @node.name,
            replication_password: replication_password
          })
        
        # Configure the replica node to follow the primary
        AnsibleRunService.new.perform(@node.id, "configure_replica.yml", 
          vars: { 
            primary_ip: primary_ip,
            primary_node_name: primary_node.name,
            replication_password: replication_password
          })
      else
        # Standard node creation (now replica-ready by default)
        AnsibleRunService.new.perform(@node.id, "create_node.yml")
      end
    end
  end
end
