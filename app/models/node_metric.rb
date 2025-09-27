class NodeMetric < ApplicationRecord
  belongs_to :node

  validates :collected_at, presence: true
  validates :cpu_usage_percent, presence: true,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :memory_total_mb, presence: true, numericality: { greater_than: 0 }
  validates :memory_used_mb, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :memory_available_mb, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :uptime_seconds, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Scopes for efficient querying
  scope :recent, -> { order(collected_at: :desc) }
  scope :for_node, ->(node_id) { where(node_id: node_id) }
  scope :since, ->(time) { where("collected_at >= ?", time) }
  scope :between, ->(start_time, end_time) { where(collected_at: start_time..end_time) }

  # Class methods for data aggregation
  def self.latest_for_node(node_id)
    for_node(node_id).recent.first
  end

  def self.average_cpu_for_period(node_id, start_time, end_time)
    for_node(node_id).between(start_time, end_time).average(:cpu_usage_percent)
  end

  def self.max_memory_for_period(node_id, start_time, end_time)
    for_node(node_id).between(start_time, end_time).maximum(:memory_used_mb)
  end

  # Instance methods for calculated values
  def memory_usage_percent
    return 0 if memory_total_mb.nil? || memory_total_mb.zero?
    ((memory_used_mb.to_f / memory_total_mb.to_f) * 100).round(2)
  end

  def swap_usage_percent
    return 0 if swap_total_mb.nil? || swap_total_mb.zero?
    ((swap_used_mb.to_f / swap_total_mb.to_f) * 100).round(2)
  end

  def memory_free_mb
    memory_total_mb - memory_used_mb
  end

  def swap_free_mb
    return 0 if swap_total_mb.nil?
    swap_total_mb - (swap_used_mb || 0)
  end

  # Load average accessors
  def load_1min
    load_average&.dig("1min")&.to_f
  end

  def load_5min
    load_average&.dig("5min")&.to_f
  end

  def load_15min
    load_average&.dig("15min")&.to_f
  end

  # Network statistics accessors
  def network_interfaces
    network_stats&.keys || []
  end

  def network_rx_bytes(interface = "eth0")
    network_stats&.dig(interface, "rx_bytes")&.to_i || 0
  end

  def network_tx_bytes(interface = "eth0")
    network_stats&.dig(interface, "tx_bytes")&.to_i || 0
  end

  def network_rx_packets(interface = "eth0")
    network_stats&.dig(interface, "rx_packets")&.to_i || 0
  end

  def network_tx_packets(interface = "eth0")
    network_stats&.dig(interface, "tx_packets")&.to_i || 0
  end

  # Disk usage accessors
  def disk_mounts
    disk_usage&.keys || []
  end

  def disk_usage_percent(mount = "/")
    disk_usage&.dig(mount, "usage_percent")&.to_f || 0
  end

  def disk_total_gb(mount = "/")
    disk_usage&.dig(mount, "total_gb")&.to_f || 0
  end

  def disk_used_gb(mount = "/")
    disk_usage&.dig(mount, "used_gb")&.to_f || 0
  end

  def disk_available_gb(mount = "/")
    disk_usage&.dig(mount, "available_gb")&.to_f || 0
  end

  # Uptime helpers
  def uptime_days
    (uptime_seconds / 86400.0).round(1)
  end

  def uptime_hours
    (uptime_seconds / 3600.0).round(1)
  end

  def uptime_formatted
    days = uptime_seconds / 86400
    hours = (uptime_seconds % 86400) / 3600
    minutes = (uptime_seconds % 3600) / 60

    if days > 0
      "#{days}d #{hours}h #{minutes}m"
    elsif hours > 0
      "#{hours}h #{minutes}m"
    else
      "#{minutes}m"
    end
  end

  # Health status indicators
  def cpu_status
    case cpu_usage_percent
    when 0..70
      "healthy"
    when 70..85
      "warning"
    else
      "critical"
    end
  end

  def memory_status
    case memory_usage_percent
    when 0...75
      "healthy"
    when 75...90
      "warning"
    else
      "critical"
    end
  end

  def disk_status(mount = "/")
    usage = disk_usage_percent(mount)
    case usage
    when 0..80
      "healthy"
    when 80..90
      "warning"
    else
      "critical"
    end
  end

  def overall_health_status
    statuses = [ cpu_status, memory_status ]
    disk_mounts.each { |mount| statuses << disk_status(mount) }

    return "critical" if statuses.include?("critical")
    return "warning" if statuses.include?("warning")
    "healthy"
  end

  # JSON serialization for API responses
  def to_metrics_json
    {
      id: id,
      node_id: node_id,
      collected_at: collected_at.iso8601,
      cpu: {
        usage_percent: cpu_usage_percent,
        status: cpu_status
      },
      memory: {
        total_mb: memory_total_mb,
        used_mb: memory_used_mb,
        available_mb: memory_available_mb,
        free_mb: memory_free_mb,
        usage_percent: memory_usage_percent,
        status: memory_status
      },
      swap: {
        total_mb: swap_total_mb,
        used_mb: swap_used_mb,
        free_mb: swap_free_mb,
        usage_percent: swap_usage_percent
      },
      disk: disk_usage,
      network: network_stats,
      load_average: load_average,
      uptime: {
        seconds: uptime_seconds,
        formatted: uptime_formatted,
        days: uptime_days
      },
      health_status: overall_health_status
    }
  end
end
