class NodeDashboardsController < ApplicationController
  before_action :find_node

  # GET /nodes/:node_id/dashboard
  def show
    @latest_metrics = @node.latest_metrics
    @metrics_history = @node.metrics_since(1.hour.ago).limit(60) # Last hour of data

    # Calculate summary statistics
    @summary_stats = calculate_summary_stats

    # Health status and alerts
    @health_status = @node.current_health_status
    @alerts = check_for_alerts

    respond_to do |format|
      format.html
      format.json do
        render json: {
          node: node_summary,
          latest_metrics: @latest_metrics&.to_metrics_json,
          metrics_history: @metrics_history.map(&:to_metrics_json),
          summary_stats: @summary_stats,
          health_status: @health_status,
          alerts: @alerts
        }
      end
    end
  end

  # GET /nodes/:node_id/dashboard/metrics_data
  def metrics_data
    # Get metrics for the specified time range
    time_range = params[:range] || "1h"
    start_time = case time_range
    when "15m" then 15.minutes.ago
    when "1h" then 1.hour.ago
    when "6h" then 6.hours.ago
    when "24h" then 24.hours.ago
    when "7d" then 7.days.ago
    else 1.hour.ago
    end

    metrics = @node.metrics_since(start_time).recent.limit(500)

    # Format data for charts
    chart_data = format_metrics_for_charts(metrics)

    render json: {
      time_range: time_range,
      start_time: start_time.iso8601,
      end_time: Time.current.iso8601,
      data: chart_data,
      summary: calculate_range_summary(metrics)
    }
  end

  # GET /nodes/:node_id/dashboard/live_metrics
  def live_metrics
    # Return the latest metrics for live updates
    latest = @node.latest_metrics

    if latest
      render json: {
        success: true,
        metrics: latest.to_metrics_json,
        timestamp: Time.current.iso8601
      }
    else
      render json: {
        success: false,
        message: "No metrics available"
      }
    end
  end

  private

  def find_node
    @node = Node.find(params[:node_id])
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_to root_path, alert: "Node not found" }
      format.json { render json: { error: "Node not found" }, status: :not_found }
    end
  end

  def node_summary
    {
      id: @node.id,
      name: @node.name,
      status: @node.status,
      cluster_id: @node.cluster_id,
      cluster_name: @node.cluster.name,
      database_type: @node.database_type_name,
      database_version: @node.database_version,
      is_replica: @node.replica?,
      ip_address: @node.get_ip_address,
      created_at: @node.created_at.iso8601,
      uptime: @latest_metrics&.uptime_formatted
    }
  end

  def calculate_summary_stats
    return {} unless @metrics_history.any?

    cpu_values = @metrics_history.map(&:cpu_usage_percent).compact
    memory_values = @metrics_history.map(&:memory_usage_percent).compact

    {
      cpu: {
        current: @latest_metrics&.cpu_usage_percent,
        average: cpu_values.any? ? (cpu_values.sum / cpu_values.size).round(2) : 0,
        max: cpu_values.max || 0,
        min: cpu_values.min || 0
      },
      memory: {
        current: @latest_metrics&.memory_usage_percent,
        average: memory_values.any? ? (memory_values.sum / memory_values.size).round(2) : 0,
        max: memory_values.max || 0,
        min: memory_values.min || 0,
        total_mb: @latest_metrics&.memory_total_mb
      },
      disk: disk_summary,
      network: network_summary,
      uptime: @latest_metrics&.uptime_seconds
    }
  end

  def disk_summary
    return {} unless @latest_metrics

    disk_data = {}
    @latest_metrics.disk_mounts.each do |mount|
      disk_data[mount] = {
        usage_percent: @latest_metrics.disk_usage_percent(mount),
        total_gb: @latest_metrics.disk_total_gb(mount),
        used_gb: @latest_metrics.disk_used_gb(mount),
        available_gb: @latest_metrics.disk_available_gb(mount),
        status: @latest_metrics.disk_status(mount)
      }
    end
    disk_data
  end

  def network_summary
    return {} unless @latest_metrics

    network_data = {}
    @latest_metrics.network_interfaces.each do |interface|
      network_data[interface] = {
        rx_bytes: @latest_metrics.network_rx_bytes(interface),
        tx_bytes: @latest_metrics.network_tx_bytes(interface),
        rx_packets: @latest_metrics.network_rx_packets(interface),
        tx_packets: @latest_metrics.network_tx_packets(interface)
      }
    end
    network_data
  end

  def check_for_alerts
    alerts = []
    return alerts unless @latest_metrics

    # CPU alerts
    if @latest_metrics.cpu_usage_percent > 85
      alerts << {
        type: "critical",
        category: "cpu",
        message: "High CPU usage: #{@latest_metrics.cpu_usage_percent}%",
        threshold: 85,
        current_value: @latest_metrics.cpu_usage_percent
      }
    elsif @latest_metrics.cpu_usage_percent > 70
      alerts << {
        type: "warning",
        category: "cpu",
        message: "Elevated CPU usage: #{@latest_metrics.cpu_usage_percent}%",
        threshold: 70,
        current_value: @latest_metrics.cpu_usage_percent
      }
    end

    # Memory alerts
    memory_percent = @latest_metrics.memory_usage_percent
    if memory_percent > 90
      alerts << {
        type: "critical",
        category: "memory",
        message: "High memory usage: #{memory_percent}%",
        threshold: 90,
        current_value: memory_percent
      }
    elsif memory_percent > 75
      alerts << {
        type: "warning",
        category: "memory",
        message: "Elevated memory usage: #{memory_percent}%",
        threshold: 75,
        current_value: memory_percent
      }
    end

    # Disk alerts
    @latest_metrics.disk_mounts.each do |mount|
      usage = @latest_metrics.disk_usage_percent(mount)
      if usage > 90
        alerts << {
          type: "critical",
          category: "disk",
          message: "High disk usage on #{mount}: #{usage}%",
          threshold: 90,
          current_value: usage,
          mount: mount
        }
      elsif usage > 80
        alerts << {
          type: "warning",
          category: "disk",
          message: "Elevated disk usage on #{mount}: #{usage}%",
          threshold: 80,
          current_value: usage,
          mount: mount
        }
      end
    end

    alerts
  end

  def format_metrics_for_charts(metrics)
    {
      cpu: metrics.map { |m| { x: m.collected_at.to_i * 1000, y: m.cpu_usage_percent } },
      memory: metrics.map { |m| { x: m.collected_at.to_i * 1000, y: m.memory_usage_percent } },
      load_average: {
        load_1min: metrics.map { |m| { x: m.collected_at.to_i * 1000, y: m.load_1min } },
        load_5min: metrics.map { |m| { x: m.collected_at.to_i * 1000, y: m.load_5min } },
        load_15min: metrics.map { |m| { x: m.collected_at.to_i * 1000, y: m.load_15min } }
      },
      disk_usage: format_disk_chart_data(metrics),
      network: format_network_chart_data(metrics)
    }
  end

  def format_disk_chart_data(metrics)
    disk_data = {}

    # Get all unique mount points
    all_mounts = metrics.flat_map(&:disk_mounts).uniq

    all_mounts.each do |mount|
      disk_data[mount] = metrics.map do |m|
        { x: m.collected_at.to_i * 1000, y: m.disk_usage_percent(mount) }
      end
    end

    disk_data
  end

  def format_network_chart_data(metrics)
    network_data = {}

    # Get all unique network interfaces
    all_interfaces = metrics.flat_map(&:network_interfaces).uniq

    all_interfaces.each do |interface|
      network_data[interface] = {
        rx_bytes: metrics.map { |m| { x: m.collected_at.to_i * 1000, y: m.network_rx_bytes(interface) } },
        tx_bytes: metrics.map { |m| { x: m.collected_at.to_i * 1000, y: m.network_tx_bytes(interface) } }
      }
    end

    network_data
  end

  def calculate_range_summary(metrics)
    return {} if metrics.empty?

    cpu_values = metrics.map(&:cpu_usage_percent).compact
    memory_values = metrics.map(&:memory_usage_percent).compact

    {
      cpu: {
        average: cpu_values.any? ? (cpu_values.sum / cpu_values.size).round(2) : 0,
        max: cpu_values.max || 0,
        min: cpu_values.min || 0
      },
      memory: {
        average: memory_values.any? ? (memory_values.sum / memory_values.size).round(2) : 0,
        max: memory_values.max || 0,
        min: memory_values.min || 0
      },
      data_points: metrics.size,
      time_span: "#{((metrics.last.collected_at - metrics.first.collected_at) / 1.hour).round(1)} hours"
    }
  end
end
