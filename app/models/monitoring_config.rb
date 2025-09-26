class MonitoringConfig < ApplicationRecord
  belongs_to :node

  validates :config_type, presence: true,
            inclusion: { in: %w[cpu memory disk network load_average] }
  validates :config_type, uniqueness: { scope: :node_id }
  validates :thresholds, presence: true

  # Default threshold configurations
  DEFAULT_THRESHOLDS = {
    'cpu' => {
      'warning' => 70.0,
      'critical' => 85.0
    },
    'memory' => {
      'warning' => 75.0,
      'critical' => 90.0
    },
    'disk' => {
      'warning' => 80.0,
      'critical' => 90.0
    },
    'load_average' => {
      'warning' => 2.0,
      'critical' => 4.0
    },
    'network' => {
      'rx_bytes_per_sec_warning' => 100_000_000, # 100 MB/s
      'rx_bytes_per_sec_critical' => 500_000_000, # 500 MB/s
      'tx_bytes_per_sec_warning' => 100_000_000,
      'tx_bytes_per_sec_critical' => 500_000_000
    }
  }.freeze

  # Scopes
  scope :enabled, -> { where(enabled: true) }
  scope :for_type, ->(type) { where(config_type: type) }

  # Class methods
  def self.default_config_for_node(node, config_type)
    find_or_create_by(node: node, config_type: config_type) do |config|
      config.thresholds = DEFAULT_THRESHOLDS[config_type] || {}
      config.enabled = true
    end
  end

  def self.ensure_default_configs_for_node(node)
    DEFAULT_THRESHOLDS.keys.each do |config_type|
      default_config_for_node(node, config_type)
    end
  end

  # Instance methods
  def warning_threshold(metric = nil)
    if metric
      thresholds.dig("#{metric}_warning") || thresholds['warning']
    else
      thresholds['warning']
    end
  end

  def critical_threshold(metric = nil)
    if metric
      thresholds.dig("#{metric}_critical") || thresholds['critical']
    else
      thresholds['critical']
    end
  end

  def check_threshold(value, metric = nil)
    return 'unknown' unless enabled? && value.present?

    critical = critical_threshold(metric)
    warning = warning_threshold(metric)

    return 'critical' if critical && value >= critical
    return 'warning' if warning && value >= warning
    'healthy'
  end

  def update_threshold(level, value, metric = nil)
    key = metric ? "#{metric}_#{level}" : level.to_s
    self.thresholds = thresholds.merge(key => value.to_f)
    save!
  end

  # Validation methods
  def validate_cpu_thresholds
    return unless config_type == 'cpu'

    warning = thresholds['warning']
    critical = thresholds['critical']

    errors.add(:thresholds, 'CPU warning threshold must be between 0 and 100') if warning && (warning < 0 || warning > 100)
    errors.add(:thresholds, 'CPU critical threshold must be between 0 and 100') if critical && (critical < 0 || critical > 100)
    errors.add(:thresholds, 'CPU critical threshold must be greater than warning threshold') if warning && critical && critical <= warning
  end

  def validate_memory_thresholds
    return unless config_type == 'memory'

    warning = thresholds['warning']
    critical = thresholds['critical']

    errors.add(:thresholds, 'Memory warning threshold must be between 0 and 100') if warning && (warning < 0 || warning > 100)
    errors.add(:thresholds, 'Memory critical threshold must be between 0 and 100') if critical && (critical < 0 || critical > 100)
    errors.add(:thresholds, 'Memory critical threshold must be greater than warning threshold') if warning && critical && critical <= warning
  end

  def validate_disk_thresholds
    return unless config_type == 'disk'

    warning = thresholds['warning']
    critical = thresholds['critical']

    errors.add(:thresholds, 'Disk warning threshold must be between 0 and 100') if warning && (warning < 0 || warning > 100)
    errors.add(:thresholds, 'Disk critical threshold must be between 0 and 100') if critical && (critical < 0 || critical > 100)
    errors.add(:thresholds, 'Disk critical threshold must be greater than warning threshold') if warning && critical && critical <= warning
  end

  validate :validate_cpu_thresholds
  validate :validate_memory_thresholds
  validate :validate_disk_thresholds
end
