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
    time_range = params[:range] || "1h"
    start_time = case time_range
    when "15m" then 15.minutes.ago
    when "1h" then 1.hour.ago
    when "6h" then 6.hours.ago
    when "24h" then 24.hours.ago
    when "7d" then 7.days.ago
    else 1.hour.ago
    end

    cluster_metrics = calculate_cluster_metrics_for_period(start_time)

    render json: {
      time_range: time_range,
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

    cpu_values = nodes_with_metrics.map { |node| node.latest_metrics.cpu_usage_percent }.compact
    memory_values = nodes_with_metrics.map { |node| node.latest_metrics.memory_usage_percent }.compact

    total_memory_mb = nodes_with_metrics.sum { |node| node.latest_metrics.memory_total_mb || 0 }
    used_memory_mb = nodes_with_metrics.sum { |node| node.latest_metrics.memory_used_mb || 0 }

    # Calculate disk usage across all nodes
    disk_stats = calculate_cluster_disk_stats(nodes_with_metrics)

    {
      cpu: {
        average: cpu_values.any? ? (cpu_values.sum / cpu_values.size).round(2) : 0,
        max: cpu_values.max || 0,
        min: cpu_values.min || 0,
        nodes_reporting: cpu_values.size
      },
      memory: {
        average: memory_values.any? ? (memory_values.sum / memory_values.size).round(2) : 0,
        max: memory_values.max || 0,
        min: memory_values.min || 0,
        total_mb: total_memory_mb,
        used_mb: used_memory_mb,
        usage_percent: total_memory_mb > 0 ? ((used_memory_mb.to_f / total_memory_mb) * 100).round(2) : 0,
        nodes_reporting: memory_values.size
      },
      disk: disk_stats,
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

  def calculate_cluster_disk_stats(nodes_with_metrics)
    total_disk_gb = 0
    used_disk_gb = 0
    disk_mount_stats = {}

    nodes_with_metrics.each do |node|
      metrics = node.latest_metrics
      next unless metrics

      metrics.disk_mounts.each do |mount|
        total_gb = metrics.disk_total_gb(mount)
        used_gb = metrics.disk_used_gb(mount)

        total_disk_gb += total_gb
        used_disk_gb += used_gb

        disk_mount_stats[mount] ||= { total_gb: 0, used_gb: 0, node_count: 0 }
        disk_mount_stats[mount][:total_gb] += total_gb
        disk_mount_stats[mount][:used_gb] += used_gb
        disk_mount_stats[mount][:node_count] += 1
      end
    end

    # Calculate usage percentages for each mount
    disk_mount_stats.each do |mount, stats|
      stats[:usage_percent] = stats[:total_gb] > 0 ? ((stats[:used_gb] / stats[:total_gb]) * 100).round(2) : 0
    end

    {
      total_gb: total_disk_gb.round(2),
      used_gb: used_disk_gb.round(2),
      available_gb: (total_disk_gb - used_disk_gb).round(2),
      usage_percent: total_disk_gb > 0 ? ((used_disk_gb / total_disk_gb) * 100).round(2) : 0,
      mount_stats: disk_mount_stats
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
    alerts = []

    @nodes.each do |node|
      latest_metrics = node.latest_metrics
      next unless latest_metrics

      # CPU alerts
      if latest_metrics.cpu_usage_percent > 85
        alerts << {
          node_id: node.id,
          node_name: node.name,
          type: "critical",
          category: "cpu",
          message: "High CPU usage: #{latest_metrics.cpu_usage_percent}%",
          value: latest_metrics.cpu_usage_percent,
          timestamp: latest_metrics.collected_at.iso8601
        }
      elsif latest_metrics.cpu_usage_percent > 70
        alerts << {
          node_id: node.id,
          node_name: node.name,
          type: "warning",
          category: "cpu",
          message: "Elevated CPU usage: #{latest_metrics.cpu_usage_percent}%",
          value: latest_metrics.cpu_usage_percent,
          timestamp: latest_metrics.collected_at.iso8601
        }
      end

      # Memory alerts
      memory_percent = latest_metrics.memory_usage_percent
      if memory_percent > 90
        alerts << {
          node_id: node.id,
          node_name: node.name,
          type: "critical",
          category: "memory",
          message: "High memory usage: #{memory_percent}%",
          value: memory_percent,
          timestamp: latest_metrics.collected_at.iso8601
        }
      elsif memory_percent > 75
        alerts << {
          node_id: node.id,
          node_name: node.name,
          type: "warning",
          category: "memory",
          message: "Elevated memory usage: #{memory_percent}%",
          value: memory_percent,
          timestamp: latest_metrics.collected_at.iso8601
        }
      end

      # Disk alerts
      latest_metrics.disk_mounts.each do |mount|
        usage = latest_metrics.disk_usage_percent(mount)
        if usage > 90
          alerts << {
            node_id: node.id,
            node_name: node.name,
            type: "critical",
            category: "disk",
            message: "High disk usage on #{mount}: #{usage}%",
            value: usage,
            mount: mount,
            timestamp: latest_metrics.collected_at.iso8601
          }
        elsif usage > 80
          alerts << {
            node_id: node.id,
            node_name: node.name,
            type: "warning",
            category: "disk",
            message: "Elevated disk usage on #{mount}: #{usage}%",
            value: usage,
            mount: mount,
            timestamp: latest_metrics.collected_at.iso8601
          }
        end
      end
    end

    # Sort by severity and timestamp
    alerts.sort_by { |alert| [ alert[:type] == "critical" ? 0 : 1, alert[:timestamp] ] }.reverse
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
      if metrics.any?
        cpu_values = metrics.map(&:cpu_usage_percent).compact
        memory_values = metrics.map(&:memory_usage_percent).compact

        node_metrics[node.id] = {
          node_name: node.name,
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
          data_points: metrics.size
        }
      end
    end

    node_metrics
  end
end
