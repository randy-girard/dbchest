class NodeMetricsChannel < ApplicationCable::Channel
  def subscribed
    # Subscribe to all node metrics updates by default
    stream_from "node_metrics_updates"
    Rails.logger.info "NodeMetricsChannel: Client subscribed to general metrics stream 'node_metrics_updates'"

    # Also subscribe to cluster and node specific streams if params are available
    if params[:node_id].present?
      stream_from "node_metrics_#{params[:node_id]}"
      Rails.logger.info "NodeMetricsChannel: Client auto-subscribed to node #{params[:node_id]} metrics"
    end

    if params[:cluster_id].present?
      stream_from "cluster_#{params[:cluster_id]}_metrics"
      Rails.logger.info "NodeMetricsChannel: Client auto-subscribed to cluster #{params[:cluster_id]} metrics"
    end
  end

  def unsubscribed
    Rails.logger.info "NodeMetricsChannel: Client unsubscribed from metrics updates"
  end

  def subscribe_to_node(data)
    # Subscribe to a specific node's metrics updates
    node_id = data["node_id"]
    if node_id.present?
      stream_from "node_metrics_#{node_id}"
      Rails.logger.info "NodeMetricsChannel: Client manually subscribed to node #{node_id} metrics stream 'node_metrics_#{node_id}'"
    end
  end

  def subscribe_to_cluster(data)
    # Subscribe to all node metrics in a specific cluster
    cluster_id = data["cluster_id"]
    if cluster_id.present?
      stream_from "cluster_#{cluster_id}_metrics"
      Rails.logger.info "NodeMetricsChannel: Client manually subscribed to cluster #{cluster_id} metrics stream 'cluster_#{cluster_id}_metrics'"
    end
  end

  def unsubscribe_from_node(data)
    # Unsubscribe from a specific node's metrics updates
    node_id = data["node_id"]
    if node_id.present?
      stop_stream_from "node_metrics_#{node_id}"
      Rails.logger.info "NodeMetricsChannel: Client unsubscribed from node #{node_id} metrics stream"
    end
  end

  def unsubscribe_from_cluster(data)
    # Unsubscribe from cluster metrics updates
    cluster_id = data["cluster_id"]
    if cluster_id.present?
      stop_stream_from "cluster_#{cluster_id}_metrics"
      Rails.logger.info "NodeMetricsChannel: Client unsubscribed from cluster #{cluster_id} metrics stream"
    end
  end
end
