class ClusterDashboardsController < ApplicationController
  before_action :find_cluster

  # GET /clusters/:cluster_id/dashboard
  def show
    @nodes = @cluster.nodes.includes(:node_metrics)
    @cluster_metrics = calculate_cluster_metrics
    @cluster_health = calculate_cluster_health
    @recent_alerts = collect_recent_alerts

    respond_to do |format|
      format.html
      format.json do
        render json: {
          cluster: cluster_summary,
          nodes: @nodes.map { |node| node_summary_with_metrics(node) },
          cluster_metrics: @cluster_metrics,
          cluster_health: @cluster_health,
          recent_alerts: @recent_alerts
        }
      end
    end
  end

  # GET /clusters/:cluster_id/dashboard/metrics_summary
  def metrics_summary
    time_parser = TimeRangeParser.new(params[:range])
    start_time = time_parser.start_time

    cluster_metrics = calculate_cluster_metrics_for_period(start_time)

    render json: {
      time_range: time_parser.range,
      start_time: start_time.iso8601,
      end_time: Time.current.iso8601,
      cluster_metrics: cluster_metrics,
      node_metrics: calculate_individual_node_metrics_for_period(start_time)
    }
  end

  # GET /clusters/:cluster_id/dashboard/live_status
  def live_status
    @nodes = @cluster.nodes.includes(:node_metrics)

    render json: {
      cluster_id: @cluster.id,
      timestamp: Time.current.iso8601,
      nodes: @nodes.map { |node|
        latest_metrics = node.latest_metrics
        {
          id: node.id,
          name: node.name,
          status: node.status,
          health_status: node.current_health_status,
          latest_metrics: latest_metrics&.to_metrics_json,
          last_seen: latest_metrics&.collected_at&.iso8601
        }
      },
      cluster_health: calculate_cluster_health
    }
  end

  private

  def find_cluster
    @cluster = Cluster.find(params[:cluster_id])
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_to root_path, alert: "Cluster not found" }
      format.json { render json: { error: "Cluster not found" }, status: :not_found }
    end
  end

  def cluster_summary
    {
      id: @cluster.id,
      name: @cluster.name,
      database_type: @cluster.database_type.name,
      node_count: @nodes.count,
      active_nodes: @nodes.where(status: "active").count,
      primary_nodes: @nodes.where(parent_node_id: nil).count,
      replica_nodes: @nodes.where.not(parent_node_id: nil).count,
      created_at: @cluster.created_at.iso8601
    }
  end

  def node_summary_with_metrics(node)
    latest_metrics = node.latest_metrics

    {
      id: node.id,
      name: node.name,
      status: node.status,
      is_replica: node.replica?,
      ip_address: node.get_ip_address,
      health_status: node.current_health_status,
      latest_metrics: latest_metrics&.to_metrics_json,
      last_metrics_at: latest_metrics&.collected_at&.iso8601,
      dashboard_url: node_dashboard_path(node)
    }
  end

  def calculate_cluster_metrics
    active_nodes = @nodes.where(status: "active")
    nodes_with_metrics = active_nodes.select { |node| node.latest_metrics.present? }

    return {} if nodes_with_metrics.empty?

    calculator = MetricsStatisticsCalculator.for_nodes(nodes_with_metrics)
    memory_totals = calculator.memory_totals

    {
      cpu: calculator.cpu_statistics,
      memory: calculator.memory_statistics.merge(
        total_mb: memory_totals[:total_mb],
        used_mb: memory_totals[:used_mb],
        usage_percent: memory_totals[:total_mb] > 0 ? ((memory_totals[:used_mb].to_f / memory_totals[:total_mb]) * 100).round(2) : 0
      ),
      disk: calculator.disk_statistics,
      nodes: {
        total: @nodes.count,
        active: active_nodes.count,
        with_metrics: nodes_with_metrics.size,
        healthy: nodes_with_metrics.count { |node| node.current_health_status == "healthy" },
        warning: nodes_with_metrics.count { |node| node.current_health_status == "warning" },
        critical: nodes_with_metrics.count { |node| node.current_health_status == "critical" }
      }
    }
  end

  def calculate_cluster_health
    active_nodes = @nodes.where(status: "active")
    nodes_with_metrics = active_nodes.select { |node| node.latest_metrics.present? }

    if nodes_with_metrics.empty?
      return {
        status: "unknown",
        message: "No metrics available",
        healthy_nodes: 0,
        warning_nodes: 0,
        critical_nodes: 0,
        total_nodes: active_nodes.count
      }
    end

    health_counts = {
      "healthy" => 0,
      "warning" => 0,
      "critical" => 0,
      "unknown" => 0
    }

    nodes_with_metrics.each do |node|
      status = node.current_health_status
      health_counts[status] = (health_counts[status] || 0) + 1
    end

    # Determine overall cluster health
    overall_status = if health_counts["critical"] > 0
                       "critical"
    elsif health_counts["warning"] > 0
                       "warning"
    elsif health_counts["healthy"] > 0
                       "healthy"
    else
                       "unknown"
    end

    message = case overall_status
    when "critical"
                "#{health_counts['critical']} node(s) in critical state"
    when "warning"
                "#{health_counts['warning']} node(s) need attention"
    when "healthy"
                "All nodes operating normally"
    else
                "Unable to determine cluster health"
    end

    {
      status: overall_status,
      message: message,
      healthy_nodes: health_counts["healthy"],
      warning_nodes: health_counts["warning"],
      critical_nodes: health_counts["critical"],
      unknown_nodes: health_counts["unknown"],
      total_nodes: nodes_with_metrics.size,
      nodes_without_metrics: active_nodes.count - nodes_with_metrics.size
    }
  end

  def collect_recent_alerts
    AlertGenerationService.for_nodes(@nodes)
  end

  def calculate_cluster_metrics_for_period(start_time)
    # This would involve more complex aggregation queries
    # For now, return current metrics
    calculate_cluster_metrics
  end

  def calculate_individual_node_metrics_for_period(start_time)
    node_metrics = {}

    @nodes.each do |node|
      metrics = node.metrics_since(start_time).recent.limit(100)
      next unless metrics.any?

      calculator = MetricsStatisticsCalculator.new(metrics)

      node_metrics[node.id] = {
        node_name: node.name,
        cpu: calculator.cpu_statistics.except(:nodes_reporting),
        memory: calculator.memory_statistics.except(:nodes_reporting),
        data_points: metrics.size
      }
    end

    node_metrics
  end
end
