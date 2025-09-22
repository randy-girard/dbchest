class CreateService
  include Sidekiq::Job

  def initialize
  end

  def perform(node_id, is_replica = false)
    @node = Node.find_by_id(node_id)
    if @node
      @node.update_status!('provisioning', 'Starting infrastructure provisioning...')
      
      # Create infrastructure with cloud-init setup (includes replication setup for replicas)
      TerraformCreateService.new.perform(@node.id)
      
      # For replicas, configure the primary node now that replica has an IP address
      if is_replica && @node.replica?
        Rails.logger.info "Configuring primary node #{@node.parent_node.id} for new replica #{@node.id} (replica now has IP)"
        @node.update_status!('provisioning', 'Configuring primary node for specific replica IP...')
        
        # Add replication user and pg_hba entry for this specific replica IP
        ReplicaConfigurationService.new.configure_primary_for_replica(@node.parent_node.id, @node.id)
      end
      
      # Status updates will come via callback API from cloud-init
      # For replicas, the cloud-init script will trigger primary configuration when it has an IP
    end
  rescue => e
    Rails.logger.error "Error in CreateService for node #{node_id}: #{e.message}"
    @node&.update_status!('error', "Failed: #{e.message}")
    raise e
  end
end
