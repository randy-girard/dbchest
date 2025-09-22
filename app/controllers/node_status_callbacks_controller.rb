class NodeStatusCallbacksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def update
    @node = Node.find(params[:id])

    status = params[:status]
    message = params[:message]

    Rails.logger.info "Received cloud-init callback for node #{@node.id}: status=#{status}, message=#{message}"

    # Handle special callback to configure primary for replica
    if status == 'configure_primary_for_replica'
      handle_configure_primary_for_replica(@node, message)
      render json: { success: true }
      return
    end

    # Validate status
    unless Node::STATUSES.key?(status)
      render json: { error: 'Invalid status' }, status: :bad_request
      return
    end

    # Update node status
    @node.update_status!(status, message)

    render json: { success: true }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Node not found' }, status: :not_found
  rescue => e
    Rails.logger.error "Error in cloud-init callback for node #{params[:id]}: #{e.message}"
    render json: { error: 'Internal server error' }, status: :internal_server_error
  end

  private

  def handle_configure_primary_for_replica(replica_node, message)
    Rails.logger.info "Configuring primary for replica #{replica_node.id}: #{message}"

    # Extract replica IP from message (format: "Configure primary for replica at IP_ADDRESS")
    replica_ip = message.match(/at\s+(\d+\.\d+\.\d+\.\d+)/i)&.captures&.first

    if replica_ip.nil?
      Rails.logger.error "Could not extract replica IP from message: #{message}"
      return
    end

    primary_node = replica_node.parent_node
    if primary_node.nil?
      Rails.logger.error "Replica node #{replica_node.id} has no parent node"
      return
    end

    Rails.logger.info "Triggering Ansible job to configure primary #{primary_node.id} for replica #{replica_node.id} at IP #{replica_ip}"

    # Queue Ansible job to configure primary for this specific replica IP
    ConfigurePrimaryForReplicaJob.perform_later(
      primary_node_id: primary_node.id,
      replica_node_id: replica_node.id,
      replica_ip: replica_ip
    )

    # Update the replica status to indicate we're waiting for primary configuration
    replica_node.update_status!('configuring', "Waiting for primary configuration for IP #{replica_ip}")
  end
end
