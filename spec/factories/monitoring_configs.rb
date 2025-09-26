FactoryBot.define do
  factory :monitoring_config do
    association :node
    config_type { 'cpu' }
    enabled { true }
    
    thresholds do
      case config_type
      when 'cpu'
        {
          'warning' => 70.0,
          'critical' => 85.0
        }
      when 'memory'
        {
          'warning' => 75.0,
          'critical' => 90.0
        }
      when 'disk'
        {
          'warning' => 80.0,
          'critical' => 90.0
        }
      when 'load_average'
        {
          'warning' => 2.0,
          'critical' => 4.0
        }
      when 'network'
        {
          'rx_bytes_per_sec_warning' => 100_000_000,
          'rx_bytes_per_sec_critical' => 500_000_000,
          'tx_bytes_per_sec_warning' => 100_000_000,
          'tx_bytes_per_sec_critical' => 500_000_000
        }
      else
        {}
      end
    end

    trait :cpu_config do
      config_type { 'cpu' }
      thresholds do
        {
          'warning' => 70.0,
          'critical' => 85.0
        }
      end
    end

    trait :memory_config do
      config_type { 'memory' }
      thresholds do
        {
          'warning' => 75.0,
          'critical' => 90.0
        }
      end
    end

    trait :disk_config do
      config_type { 'disk' }
      thresholds do
        {
          'warning' => 80.0,
          'critical' => 90.0
        }
      end
    end

    trait :load_average_config do
      config_type { 'load_average' }
      thresholds do
        {
          'warning' => 2.0,
          'critical' => 4.0
        }
      end
    end

    trait :network_config do
      config_type { 'network' }
      thresholds do
        {
          'rx_bytes_per_sec_warning' => 100_000_000,
          'rx_bytes_per_sec_critical' => 500_000_000,
          'tx_bytes_per_sec_warning' => 100_000_000,
          'tx_bytes_per_sec_critical' => 500_000_000
        }
      end
    end

    trait :disabled do
      enabled { false }
    end

    trait :strict_thresholds do
      thresholds do
        case config_type
        when 'cpu'
          {
            'warning' => 50.0,
            'critical' => 70.0
          }
        when 'memory'
          {
            'warning' => 60.0,
            'critical' => 80.0
          }
        when 'disk'
          {
            'warning' => 70.0,
            'critical' => 85.0
          }
        else
          {}
        end
      end
    end

    trait :relaxed_thresholds do
      thresholds do
        case config_type
        when 'cpu'
          {
            'warning' => 80.0,
            'critical' => 95.0
          }
        when 'memory'
          {
            'warning' => 85.0,
            'critical' => 95.0
          }
        when 'disk'
          {
            'warning' => 90.0,
            'critical' => 95.0
          }
        else
          {}
        end
      end
    end

    trait :custom_thresholds do
      thresholds do
        {
          'warning' => 60.0,
          'critical' => 80.0,
          'custom_warning' => 55.0,
          'custom_critical' => 75.0
        }
      end
    end

    trait :invalid_thresholds do
      thresholds do
        {
          'warning' => 150.0, # Invalid: > 100
          'critical' => -10.0  # Invalid: < 0
        }
      end
    end

    trait :inverted_thresholds do
      thresholds do
        {
          'warning' => 90.0,
          'critical' => 70.0  # Invalid: critical < warning
        }
      end
    end
  end
end
