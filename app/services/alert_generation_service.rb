# frozen_string_literal: true

# Service for generating alerts based on node metrics and thresholds
class AlertGenerationService
  # Default thresholds (can be overridden by MonitoringConfig)
  DEFAULT_THRESHOLDS = {
    cpu: { warning: 70, critical: 85 },
    memory: { warning: 75, critical: 90 },
    disk: { warning: 80, critical: 90 }
  }.freeze

  def initialize(node, latest_metrics)
    @node = node
    @latest_metrics = latest_metrics
  end

  def generate_alerts
    return [] unless @latest_metrics

    alerts = []
    alerts.concat(cpu_alerts)
    alerts.concat(memory_alerts)
    alerts.concat(disk_alerts)
    alerts
  end

  private

  def cpu_alerts
    usage = @latest_metrics.cpu_usage_percent
    thresholds = DEFAULT_THRESHOLDS[:cpu]

    generate_alert_for_metric(
      usage: usage,
      thresholds: thresholds,
      category: "cpu",
      message_template: "CPU usage: %{usage}%"
    )
  end

  def memory_alerts
    usage = @latest_metrics.memory_usage_percent
    thresholds = DEFAULT_THRESHOLDS[:memory]

    generate_alert_for_metric(
      usage: usage,
      thresholds: thresholds,
      category: "memory",
      message_template: "Memory usage: %{usage}%"
    )
  end

  def disk_alerts
    alerts = []
    thresholds = DEFAULT_THRESHOLDS[:disk]

    @latest_metrics.disk_mounts.each do |mount|
      usage = @latest_metrics.disk_usage_percent(mount)

      mount_alerts = generate_alert_for_metric(
        usage: usage,
        thresholds: thresholds,
        category: "disk",
        message_template: "Disk usage on #{mount}: %{usage}%",
        mount: mount
      )

      alerts.concat(mount_alerts)
    end

    alerts
  end

  def generate_alert_for_metric(usage:, thresholds:, category:, message_template:, mount: nil)
    alert_type = determine_alert_type(usage, thresholds)
    return [] if alert_type.nil?

    alert_data = {
      type: alert_type,
      category: category,
      message: format(message_template, usage: usage),
      threshold: thresholds[alert_type],
      current_value: usage
    }

    alert_data[:mount] = mount if mount
    alert_data[:timestamp] = @latest_metrics.collected_at.iso8601 if include_timestamp?

    [ alert_data ]
  end

  def determine_alert_type(usage, thresholds)
    return "critical" if usage > thresholds[:critical]
    return "warning" if usage > thresholds[:warning]
    nil
  end

  def include_timestamp?
    # Include timestamp when generating alerts for cluster-wide views
    @node.nil? || @latest_metrics.respond_to?(:collected_at)
  end

  class << self
    # Generate alerts for a single node
    def for_node(node)
      latest_metrics = node.latest_metrics
      return [] unless latest_metrics

      new(node, latest_metrics).generate_alerts
    end

    # Generate alerts for multiple nodes (e.g., cluster dashboard)
    def for_nodes(nodes)
      alerts = []

      nodes.each do |node|
        latest_metrics = node.latest_metrics
        next unless latest_metrics

        node_alerts = new(node, latest_metrics).generate_alerts
        node_alerts.each do |alert|
          alert[:node_id] = node.id
          alert[:node_name] = node.name
        end

        alerts.concat(node_alerts)
      end

      # Sort by severity and timestamp
      alerts.sort_by { |alert| [ alert[:type] == "critical" ? 0 : 1, alert[:timestamp] || "" ] }.reverse
    end
  end
end
