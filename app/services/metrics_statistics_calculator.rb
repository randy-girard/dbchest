# frozen_string_literal: true

# Service for calculating statistics from metrics collections
class MetricsStatisticsCalculator
  def initialize(metrics_collection)
    @metrics = Array(metrics_collection)
  end

  def cpu_statistics
    cpu_values = @metrics.map(&:cpu_usage_percent).compact
    calculate_statistics(cpu_values)
  end

  def memory_statistics
    memory_values = @metrics.map(&:memory_usage_percent).compact
    calculate_statistics(memory_values)
  end

  def memory_totals
    {
      total_mb: @metrics.sum { |m| m.memory_total_mb || 0 },
      used_mb: @metrics.sum { |m| m.memory_used_mb || 0 }
    }
  end

  def disk_statistics
    total_disk_gb = 0
    used_disk_gb = 0
    disk_mount_stats = {}

    @metrics.each do |metrics|
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

  private

  def calculate_statistics(values)
    return default_statistics if values.empty?

    {
      average: (values.sum / values.size.to_f).round(2),
      max: values.max,
      min: values.min,
      nodes_reporting: values.size
    }
  end

  def default_statistics
    {
      average: 0,
      max: 0,
      min: 0,
      nodes_reporting: 0
    }
  end

  class << self
    # Calculate statistics for a collection of nodes
    def for_nodes(nodes)
      metrics = nodes.map(&:latest_metrics).compact
      new(metrics)
    end

    # Calculate statistics for a single node over time
    def for_node_history(node, time_range)
      metrics = node.metrics_since(time_range)
      new(metrics)
    end
  end
end
