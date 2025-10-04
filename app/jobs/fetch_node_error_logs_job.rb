class FetchNodeErrorLogsJob < ApplicationJob
  queue_as :default
  
  # Retry with exponential backoff - node might not be SSH-accessible immediately
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  
  def perform(node_id)
    node = Node.find(node_id)
    
    Rails.logger.info "Fetching error logs for node #{node_id} (#{node.name})"
    
    # Wait a bit to ensure the node is accessible and logs are written
    sleep 5
    
    # Fetch and parse logs
    service = NodeLogFetcherService.new(node)
    result = service.fetch_and_store_error_details
    
    if result[:success]
      Rails.logger.info "Successfully fetched and stored error details for node #{node_id}"
    else
      Rails.logger.warn "Could not fetch error logs for node #{node_id}: #{result[:error]}"
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "Node #{node_id} not found when trying to fetch error logs"
  rescue => e
    Rails.logger.error "Error fetching logs for node #{node_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise # Re-raise to trigger retry
  end
end

