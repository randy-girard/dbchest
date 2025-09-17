class CreateService
  include Sidekiq::Job

  def initialize
  end

  def perform(node_id, replica: false)
    @node = Node.find_by_id(node_id)
    if @node
      TerraformCreateService.new.perform(@node.id)

      if replica && @node.replica?
        # First install PostgreSQL on the replica node
        AnsibleRunService.new.perform(@node.id, "create_node.yml")
        
        # Get primary node IP address for configuration
        primary_ip = @node.parent_node.get_runtime_config_value("ip_address")
        replica_ip = @node.get_runtime_config_value("ip_address")
        
        # Configure the primary node for replication
        AnsibleRunService.new.perform(@node.parent_node.id, "configure_primary_replication.yml", 
          vars: { 
            replica_ip: replica_ip,
            replica_node_name: @node.name
          })
        
        # Configure the replica node to follow the primary
        AnsibleRunService.new.perform(@node.id, "configure_replica.yml", 
          vars: { 
            primary_ip: primary_ip,
            primary_node_name: @node.parent_node.name
          })
      else
        # Standard node creation
        AnsibleRunService.new.perform(@node.id, "create_node.yml")
      end
    end
  end
end
