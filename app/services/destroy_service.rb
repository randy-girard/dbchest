class DestroyService
  include Sidekiq::Job

  def initialize
  end

  def perform(node_id)
    @node = Node.find_by_id(node_id)
    return unless @node

    # If this is a replica, clean up the primary's pg_hba.conf entries
    if @node.replica? && @node.parent_node.present?
      replica_ip = @node.get_runtime_config_value("ip_address")
      if replica_ip.present?
        AnsibleRunService.new.perform(@node.parent_node.id, "cleanup_replica_config.yml", 
          vars: { 
            replica_ip: replica_ip
          })
      end
    end

    TerraformDestroyService.new.perform(@node.id)

    @node.destroy!
  end
end
