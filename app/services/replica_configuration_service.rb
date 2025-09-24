require_relative 'database_service_factory'

class ReplicaConfigurationService
  def initialize
  end

  def configure_primary_for_replica(primary_node_id, replica_node_id)
    @primary_node = Node.find(primary_node_id)
    @replica_node = Node.find(replica_node_id)
    
    # Get replica IP address (should be available now after Terraform)
    replica_ip = @replica_node.get_ip_address
    if replica_ip.blank?
      raise "Cannot configure primary: Replica node #{@replica_node.id} has no IP address"
    end
    
    Rails.logger.info "Configuring primary node #{@primary_node.id} for replica #{@replica_node.name} at IP #{replica_ip}"
    
    # Use the database-specific deployment service
    deployment_service = DatabaseServiceFactory.deployment_service_for(@primary_node)
    deployment_service.configure_replication!
    
    # Create replication slot name from replica name
    slot_name = @replica_node.name.downcase.gsub(/[^a-z0-9_]/, '_')
    
    # Use Ansible to configure the primary node for this specific replica
    AnsibleRunService.new.perform(@primary_node.id, @primary_node.database_type_handler.primary_replication_playbook,
      vars: {
        replica_node_name: @replica_node.name,
        replica_ip: replica_ip,
        replication_password: @primary_node.get_replication_password,
        replication_slot_name: slot_name,
        "#{@primary_node.database_type_slug}_version" => @primary_node.database_version
      })
  end
  
  private
  
  def get_subnet_for_replication
    # Get the primary node's network configuration to determine the subnet
    primary_ip = @primary_node.get_ip_address
    if primary_ip.present?
      # For simplicity, assume /24 subnet - in production you might want to be more specific
      ip_parts = primary_ip.split('.')
      "#{ip_parts[0]}.#{ip_parts[1]}.#{ip_parts[2]}.0/24"
    else
      # Fallback to allow any IP (less secure but functional)
      "0.0.0.0/0"
    end
  end

  def configure_replica_node(replica_node_id)
    @replica_node = Node.find(replica_node_id)
    @primary_node = @replica_node.parent_node
    
    # Get IP addresses
    primary_ip = @primary_node.get_ip_address
    replica_ip = @replica_node.get_ip_address
    
    raise "Cannot configure replication: Primary node has no IP address" if primary_ip.blank?
    raise "Cannot configure replication: Replica node has no IP address" if replica_ip.blank?
    
    Rails.logger.info "Configuring replica node #{@replica_node.id} to follow primary #{@primary_node.id}"
    
    # Use the database-specific deployment service
    deployment_service = DatabaseServiceFactory.deployment_service_for(@replica_node)
    deployment_service.deploy_replica!
  end
end
