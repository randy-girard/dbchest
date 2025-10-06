# frozen_string_literal: true

# Concern for managing node metrics and health monitoring
module NodeMetricsManagement
  extend ActiveSupport::Concern

  included do
    has_many :node_metrics, dependent: :delete_all
    has_many :monitoring_configs, dependent: :delete_all

    after_create :ensure_metrics_api_key
    after_create :setup_default_monitoring_configs
  end

  # Metrics API key management
  def ensure_metrics_api_key!
    return metrics_api_key if metrics_api_key.present?

    new_key = generate_metrics_api_key
    update!(metrics_api_key: new_key)
    new_key
  end

  def regenerate_metrics_api_key!
    new_key = generate_metrics_api_key
    update!(metrics_api_key: new_key)
    new_key
  end

  def metrics_collection_url
    Rails.application.routes.url_helpers.node_metrics_url(
      self,
      host: Rails.application.config.action_mailer.default_url_options[:host]
    )
  end

  # Metrics retrieval methods
  def latest_metrics
    node_metrics.recent.first
  end

  def metrics_since(time)
    node_metrics.since(time).recent
  end

  def average_cpu_last_hour
    one_hour_ago = 1.hour.ago
    NodeMetric.average_cpu_for_period(id, one_hour_ago, Time.current)
  end

  def max_memory_last_hour
    one_hour_ago = 1.hour.ago
    NodeMetric.max_memory_for_period(id, one_hour_ago, Time.current)
  end

  # Health status methods
  def current_health_status
    latest = latest_metrics
    return "unknown" unless latest

    if monitoring_configs.enabled.any?
      check_health_with_custom_thresholds(latest)
    else
      latest.overall_health_status
    end
  end

  def monitoring_alerts
    return [] unless latest_metrics

    alerts = []
    latest = latest_metrics

    alerts.concat(cpu_alerts(latest))
    alerts.concat(memory_alerts(latest))
    alerts.concat(disk_alerts(latest))

    alerts
  end

  private

  def ensure_metrics_api_key
    ensure_metrics_api_key! if metrics_api_key.blank?
  end

  def generate_metrics_api_key
    "node_#{id}_#{SecureRandom.hex(16)}"
  end

  def setup_default_monitoring_configs
    MonitoringConfig.ensure_default_configs_for_node(self)
  end

  def check_health_with_custom_thresholds(metrics)
    statuses = []

    statuses << check_cpu_threshold(metrics)
    statuses << check_memory_threshold(metrics)
    statuses.concat(check_disk_thresholds(metrics))

    determine_overall_status(statuses)
  end

  def check_cpu_threshold(metrics)
    cpu_config = monitoring_configs.enabled.for_type("cpu").first
    cpu_config&.check_threshold(metrics.cpu_usage_percent)
  end

  def check_memory_threshold(metrics)
    memory_config = monitoring_configs.enabled.for_type("memory").first
    memory_config&.check_threshold(metrics.memory_usage_percent)
  end

  def check_disk_thresholds(metrics)
    disk_config = monitoring_configs.enabled.for_type("disk").first
    return [] unless disk_config

    metrics.disk_mounts.map do |mount|
      disk_config.check_threshold(metrics.disk_usage_percent(mount))
    end
  end

  def determine_overall_status(statuses)
    statuses.compact!
    return "critical" if statuses.include?("critical")
    return "warning" if statuses.include?("warning")
    return "healthy" if statuses.include?("healthy")
    "unknown"
  end

  def get_monitoring_config(config_type)
    monitoring_configs.for_type(config_type).first ||
      MonitoringConfig.default_config_for_node(self, config_type)
  end

  def update_monitoring_threshold(config_type, level, value, metric = nil)
    config = get_monitoring_config(config_type)
    config.update_threshold(level, value, metric)
  end

  # Alert generation methods
  def cpu_alerts(latest)
    cpu_config = get_monitoring_config("cpu")
    return [] unless cpu_config.enabled?

    status = cpu_config.check_threshold(latest.cpu_usage_percent)
    return [] if status == "healthy"

    [ {
      type: status,
      category: "cpu",
      message: "CPU usage: #{latest.cpu_usage_percent}%",
      value: latest.cpu_usage_percent,
      threshold: status == "critical" ? cpu_config.critical_threshold : cpu_config.warning_threshold
    } ]
  end

  def memory_alerts(latest)
    memory_config = get_monitoring_config("memory")
    return [] unless memory_config.enabled?

    status = memory_config.check_threshold(latest.memory_usage_percent)
    return [] if status == "healthy"

    [ {
      type: status,
      category: "memory",
      message: "Memory usage: #{latest.memory_usage_percent}%",
      value: latest.memory_usage_percent,
      threshold: status == "critical" ? memory_config.critical_threshold : memory_config.warning_threshold
    } ]
  end

  def disk_alerts(latest)
    disk_config = get_monitoring_config("disk")
    return [] unless disk_config.enabled?

    alerts = []
    latest.disk_mounts.each do |mount|
      usage = latest.disk_usage_percent(mount)
      status = disk_config.check_threshold(usage)
      next if status == "healthy"

      alerts << {
        type: status,
        category: "disk",
        message: "Disk usage on #{mount}: #{usage}%",
        value: usage,
        mount: mount,
        threshold: status == "critical" ? disk_config.critical_threshold : disk_config.warning_threshold
      }
    end
    alerts
  end
end
