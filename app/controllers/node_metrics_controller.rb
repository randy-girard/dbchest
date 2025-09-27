class NodeMetricsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_node_api_key
  before_action :find_node
  before_action :validate_node_active, only: [:create]

  # POST /nodes/:node_id/metrics
  def create
    @node_metric = @node.node_metrics.build(node_metric_params)
    
    if @node_metric.save
      Rails.logger.info "Metrics saved for node #{@node.id}: CPU #{@node_metric.cpu_usage_percent}%, Memory #{@node_metric.memory_usage_percent}%"
      
      # Broadcast metrics update via ActionCable
      broadcast_metrics_update(@node_metric)
      
      render json: { 
        success: true, 
        message: "Metrics recorded successfully",
        metric_id: @node_metric.id,
        health_status: @node_metric.overall_health_status
      }, status: :created
    else
      Rails.logger.error "Failed to save metrics for node #{@node.id}: #{@node_metric.errors.full_messages.join(', ')}"
      render json: { 
        success: false, 
        errors: @node_metric.errors.full_messages 
      }, status: :unprocessable_entity
    end
  rescue => e
    Rails.logger.error "Error processing metrics for node #{params[:node_id]}: #{e.message}"
    render json: { 
      success: false, 
      error: "Internal server error" 
    }, status: :internal_server_error
  end

  # GET /nodes/:node_id/metrics
  def index
    @metrics = @node.node_metrics.recent.limit(100)
    
    render json: {
      node_id: @node.id,
      node_name: @node.name,
      metrics: @metrics.map(&:to_metrics_json),
      latest_health_status: @node.current_health_status
    }
  end

  # GET /nodes/:node_id/metrics/latest
  def latest
    @metric = @node.latest_metrics
    
    if @metric
      render json: @metric.to_metrics_json
    else
      render json: { 
        error: "No metrics available for this node" 
      }, status: :not_found
    end
  end

  # GET /nodes/:node_id/metrics/summary
  def summary
    one_hour_ago = 1.hour.ago
    one_day_ago = 1.day.ago
    
    latest = @node.latest_metrics
    
    summary_data = {
      node_id: @node.id,
      node_name: @node.name,
      current_status: @node.status,
      health_status: @node.current_health_status,
      latest_metrics: latest&.to_metrics_json,
      averages: {
        cpu_last_hour: @node.average_cpu_last_hour&.round(2),
        max_memory_last_hour: @node.max_memory_last_hour
      },
      metrics_count: {
        last_hour: @node.node_metrics.since(one_hour_ago).count,
        last_day: @node.node_metrics.since(one_day_ago).count,
        total: @node.node_metrics.count
      },
      collection_info: {
        last_collected: latest&.collected_at&.iso8601,
        collection_url: @node.metrics_collection_url
      }
    }
    
    render json: summary_data
  end

  private

  def authenticate_node_api_key
    auth_header = request.headers['Authorization']
    
    unless auth_header&.start_with?('Bearer ')
      render json: { error: 'Missing or invalid authorization header' }, status: :unauthorized
      return
    end
    
    @api_key = auth_header.split(' ', 2).last
    
    unless @api_key.present?
      render json: { error: 'Missing API key' }, status: :unauthorized
      return
    end
  end

  def find_node
    @node = Node.find_by(id: params[:node_id])
    
    unless @node
      render json: { error: 'Node not found' }, status: :not_found
      return
    end
    
    # Verify API key matches this node
    unless @node.metrics_api_key == @api_key
      Rails.logger.warn "Invalid API key for node #{@node.id}: provided '#{@api_key}', expected '#{@node.metrics_api_key}'"
      render json: { error: 'Invalid API key for this node' }, status: :unauthorized
      return
    end
  end

  def validate_node_active
    # Allow metrics submission during setup and active states
    unless @node.active? || @node.status == 'configuring' || @node.status == 'installing' || @node.status == 'provisioning'
      render json: {
        error: 'Node must be active or configuring to submit metrics',
        current_status: @node.status
      }, status: :forbidden
      return
    end
  end

  def node_metric_params
    params.require(:node_metric).permit(
      :collected_at,
      :cpu_usage_percent,
      :memory_total_mb,
      :memory_used_mb,
      :memory_available_mb,
      :swap_total_mb,
      :swap_used_mb,
      :uptime_seconds,
      disk_usage: {},
      network_stats: {},
      load_average: {}
    )
  end

  def broadcast_metrics_update(metric)
    # Prepare broadcast data
    broadcast_data = {
      type: 'metrics_update',
      node_id: @node.id,
      node_name: @node.name,
      cluster_id: @node.cluster_id,
      metrics: metric.to_metrics_json,
      timestamp: Time.current.iso8601
    }

    Rails.logger.info "🔊 Broadcasting metrics update for node #{@node.id}"
    Rails.logger.debug "📦 Metrics broadcast data: #{broadcast_data.inspect}"

    # Broadcast to all metrics subscribers
    ActionCable.server.broadcast("node_metrics_updates", broadcast_data)
    Rails.logger.info "✅ Broadcasted to stream: node_metrics_updates"

    # Broadcast to specific node metrics subscribers
    ActionCable.server.broadcast("node_metrics_#{@node.id}", broadcast_data)
    Rails.logger.info "✅ Broadcasted to stream: node_metrics_#{@node.id}"

    # Broadcast to cluster metrics subscribers
    ActionCable.server.broadcast("cluster_#{@node.cluster_id}_metrics", broadcast_data)
    Rails.logger.info "✅ Broadcasted to stream: cluster_#{@node.cluster_id}_metrics"

    # In development, also broadcast to console channel for debugging
    if Rails.env.development?
      console_data = broadcast_data.merge({
        timestamp: Time.current.strftime("%H:%M:%S"),
        event_type: "node_metrics_update",
        cpu_usage: metric.cpu_usage_percent,
        memory_usage: metric.memory_usage_percent,
        health_status: metric.overall_health_status
      })
      ActionCable.server.broadcast("development_console", console_data)
      Rails.logger.debug "🖥️  Broadcasted metrics to development console: #{console_data.inspect}"
    end

    Rails.logger.info "🎯 Total metrics streams broadcasted to: #{Rails.env.development? ? 4 : 3}"
  rescue => e
    Rails.logger.error "Error broadcasting metrics update: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
end
