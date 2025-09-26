FactoryBot.define do
  factory :node_metric do
    association :node
    collected_at { Time.current }
    cpu_usage_percent { rand(10.0..90.0).round(1) }
    memory_total_mb { 8192 }
    memory_used_mb { rand(2048..6144) }
    memory_available_mb { memory_total_mb - memory_used_mb }
    swap_total_mb { 2048 }
    swap_used_mb { rand(0..1024) }
    uptime_seconds { rand(3600..604800) } # 1 hour to 1 week
    
    disk_usage do
      {
        '/' => {
          'usage_percent' => rand(20.0..80.0).round(1),
          'total_gb' => 100.0,
          'used_gb' => rand(20.0..80.0).round(1),
          'available_gb' => rand(20.0..80.0).round(1)
        }
      }
    end
    
    network_stats do
      {
        'eth0' => {
          'rx_bytes' => rand(1000000..10000000),
          'tx_bytes' => rand(500000..5000000),
          'rx_packets' => rand(1000..10000),
          'tx_packets' => rand(800..8000)
        }
      }
    end
    
    load_average do
      {
        '1min' => rand(0.1..3.0).round(2),
        '5min' => rand(0.1..2.5).round(2),
        '15min' => rand(0.1..2.0).round(2)
      }
    end

    trait :healthy do
      cpu_usage_percent { rand(10.0..60.0).round(1) }
      memory_used_mb { rand(2048..4096) }
      disk_usage do
        {
          '/' => {
            'usage_percent' => rand(20.0..60.0).round(1),
            'total_gb' => 100.0,
            'used_gb' => rand(20.0..60.0).round(1),
            'available_gb' => rand(40.0..80.0).round(1)
          }
        }
      end
    end

    trait :warning do
      cpu_usage_percent { rand(70.0..84.0).round(1) }
      memory_used_mb { rand(6144..7372) } # 75-90% of 8192
      disk_usage do
        {
          '/' => {
            'usage_percent' => rand(80.0..89.0).round(1),
            'total_gb' => 100.0,
            'used_gb' => rand(80.0..89.0).round(1),
            'available_gb' => rand(11.0..20.0).round(1)
          }
        }
      end
    end

    trait :critical do
      cpu_usage_percent { rand(85.0..99.0).round(1) }
      memory_used_mb { rand(7373..8192) } # 90%+ of 8192
      disk_usage do
        {
          '/' => {
            'usage_percent' => rand(90.0..99.0).round(1),
            'total_gb' => 100.0,
            'used_gb' => rand(90.0..99.0).round(1),
            'available_gb' => rand(1.0..10.0).round(1)
          }
        }
      end
    end

    trait :with_multiple_disks do
      disk_usage do
        {
          '/' => {
            'usage_percent' => rand(20.0..80.0).round(1),
            'total_gb' => 50.0,
            'used_gb' => rand(10.0..40.0).round(1),
            'available_gb' => rand(10.0..40.0).round(1)
          },
          '/var' => {
            'usage_percent' => rand(20.0..80.0).round(1),
            'total_gb' => 100.0,
            'used_gb' => rand(20.0..80.0).round(1),
            'available_gb' => rand(20.0..80.0).round(1)
          },
          '/tmp' => {
            'usage_percent' => rand(10.0..50.0).round(1),
            'total_gb' => 20.0,
            'used_gb' => rand(2.0..10.0).round(1),
            'available_gb' => rand(10.0..18.0).round(1)
          }
        }
      end
    end

    trait :with_multiple_interfaces do
      network_stats do
        {
          'eth0' => {
            'rx_bytes' => rand(1000000..10000000),
            'tx_bytes' => rand(500000..5000000),
            'rx_packets' => rand(1000..10000),
            'tx_packets' => rand(800..8000)
          },
          'eth1' => {
            'rx_bytes' => rand(500000..5000000),
            'tx_bytes' => rand(250000..2500000),
            'rx_packets' => rand(500..5000),
            'tx_packets' => rand(400..4000)
          }
        }
      end
    end

    trait :high_load do
      load_average do
        {
          '1min' => rand(3.0..8.0).round(2),
          '5min' => rand(2.5..6.0).round(2),
          '15min' => rand(2.0..4.0).round(2)
        }
      end
    end

    trait :recent do
      collected_at { rand(5.minutes.ago..Time.current) }
    end

    trait :old do
      collected_at { rand(7.days.ago..1.day.ago) }
    end

    trait :with_swap_usage do
      swap_total_mb { 4096 }
      swap_used_mb { rand(1024..2048) }
    end

    trait :no_swap do
      swap_total_mb { 0 }
      swap_used_mb { 0 }
    end
  end
end
