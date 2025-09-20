class DestroyService
  include Sidekiq::Job

  def initialize
  end

  def perform(node_id)
    @node = Node.find_by_id(node_id)
    return unless @node

    @node.update_status!('destroying', 'Starting node destruction...')

    # If this is a replica, clean up the primary's pg_hba.conf entries
    if @node.replica? && @node.parent_node.present?
      replica_ip = @node.get_ip_address
      if replica_ip.present?
        Rails.logger.info "Cleaning up pg_hba.conf entries for replica IP: #{replica_ip}"
        @node.update_status!('destroying', 'Cleaning up replication configuration...')
        AnsibleRunService.new.perform(@node.parent_node.id, "cleanup_replica_config.yml", 
          vars: { 
            replica_ip: replica_ip
          })
      else
        Rails.logger.warn "Skipping pg_hba.conf cleanup for replica node #{@node.id}: no IP address found"
      end
    end

    @node.update_status!('destroying', 'Destroying infrastructure...')
    TerraformDestroyService.new.perform(@node.id)

    @node.update_status!('destroyed', 'Node has been destroyed')
    @node.destroy!
  rescue => e
    Rails.logger.error "Error in DestroyService for node #{node_id}: #{e.message}"
    @node&.update_status!('error', "Destruction failed: #{e.message}")
    raise e
  end
end
