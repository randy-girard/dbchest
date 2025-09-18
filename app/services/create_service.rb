class CreateService
  include Sidekiq::Job

  def initialize
  end

  def perform(node_id, is_replica = false)
    @node = Node.find_by_id(node_id)
    if @node
      TerraformCreateService.new.perform(@node.id)

      if is_replica && @node.replica?
        # Install PostgreSQL on the replica node (already replica-ready)
        AnsibleRunService.new.perform(@node.id, "create_node.yml")
        
        # Get primary node and ensure replication password exists
        primary_node = @node.parent_node
        replication_password = primary_node.ensure_replication_password!
        
        # Get clean IP addresses (without subnet notation)
        primary_ip = primary_node.get_ip_address
        replica_ip = @node.get_ip_address
        
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
