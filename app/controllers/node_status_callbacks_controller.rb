class NodeStatusCallbacksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def update
    @node = Node.find(params[:id])

    status = params[:status]
    message = params[:message]

    Rails.logger.info "Received cloud-init callback for node #{@node.id}: status=#{status}, message=#{message}"

    # Validate status
    unless Node::STATUSES.key?(status)
      render json: { error: "Invalid status" }, status: :bad_request
      return
    end

    # Update node status
    @node.update_status!(status, message)

    # If node entered error state, fetch and parse cloud-init logs
    if status == "error"
      FetchNodeErrorLogsJob.perform_later(@node.id)
    end

    render json: { success: true }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Node not found" }, status: :not_found
  rescue => e
    Rails.logger.error "Error in cloud-init callback for node #{params[:id]}: #{e.message}"
    render json: { error: "Internal server error" }, status: :internal_server_error
  end
end
