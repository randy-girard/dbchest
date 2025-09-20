class NodeStatusChannel < ApplicationCable::Channel
  def subscribed
    # Subscribe to all node status updates by default
    stream_from "node_status_updates"
    Rails.logger.info "NodeStatusChannel: Client subscribed to general updates stream 'node_status_updates'"
    
    # Also subscribe to cluster and node specific streams if params are available
    if params[:node_id].present?
      stream_from "node_status_#{params[:node_id]}"
      Rails.logger.info "NodeStatusChannel: Client auto-subscribed to node #{params[:node_id]}"
    end
    
    if params[:cluster_id].present?
      stream_from "cluster_#{params[:cluster_id]}_node_status"
      Rails.logger.info "NodeStatusChannel: Client auto-subscribed to cluster #{params[:cluster_id]}"
    end
  end

  def unsubscribed
    Rails.logger.info "NodeStatusChannel: Client unsubscribed"
  end

  def subscribe_to_node(data)
    # Subscribe to a specific node's updates
    node_id = data['node_id']
    if node_id.present?
      stream_from "node_status_#{node_id}"
      Rails.logger.info "NodeStatusChannel: Client manually subscribed to node #{node_id} stream 'node_status_#{node_id}'"
    end
  end

  def subscribe_to_cluster(data)
    # Subscribe to all nodes in a specific cluster
    cluster_id = data['cluster_id']
    if cluster_id.present?
      stream_from "cluster_#{cluster_id}_node_status"
      Rails.logger.info "NodeStatusChannel: Client manually subscribed to cluster #{cluster_id} stream 'cluster_#{cluster_id}_node_status'"
    end
  end
end
