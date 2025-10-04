class CreateService
  include Sidekiq::Job

  def initialize
  end

  def perform(node_id, is_replica = false)
    @node = Node.find_by_id(node_id)
    if @node
      @node.update_status!("provisioning", "Starting infrastructure provisioning...")

      # Create infrastructure with cloud-init setup
      TerraformCreateService.new.perform(@node.id)

      # For replicas, configure the primary node now that we have the replica IP from Terraform
      if is_replica && @node.replica?
        # Reload to get the IP address from Terraform outputs
        @node.reload
        replica_ip = @node.get_ip_address

        if replica_ip.present?
          Rails.logger.info "Triggering primary configuration for replica #{@node.id} at IP #{replica_ip}"
          @node.update_status!("provisioning", "Configuring primary node for replication...")

          # Queue Ansible job to configure primary for this specific replica IP
          # This runs while cloud-init is still installing PostgreSQL on the replica
          ConfigurePrimaryForReplicaJob.perform_later(
            primary_node_id: @node.parent_node.id,
            replica_node_id: @node.id,
            replica_ip: replica_ip
          )
        else
          Rails.logger.warn "Replica #{@node.id} has no IP address after Terraform, skipping primary configuration"
        end
      end

      # Status updates will come via callback API from cloud-init
    end
  rescue => e
    Rails.logger.error "Error in CreateService for node #{node_id}: #{e.message}"
    @node&.update_status!("error", "Failed: #{e.message}")
    raise e
  end
end
