require 'rails_helper'

RSpec.describe NodeMetric, type: :model do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
  
  let(:valid_attributes) do
    {
      node: node,
      collected_at: Time.current,
      cpu_usage_percent: 45.5,
      memory_total_mb: 8192,
      memory_used_mb: 4096,
      memory_available_mb: 4096,
      swap_total_mb: 2048,
      swap_used_mb: 512,
      uptime_seconds: 86400,
      disk_usage: {
        '/' => {
          'usage_percent' => 65.0,
          'total_gb' => 100.0,
          'used_gb' => 65.0,
          'available_gb' => 35.0
        }
      },
      network_stats: {
        'eth0' => {
          'rx_bytes' => 1024000,
          'tx_bytes' => 512000,
          'rx_packets' => 1000,
          'tx_packets' => 800
        }
      },
      load_average: {
        '1min' => 1.5,
        '5min' => 1.2,
        '15min' => 1.0
      }
    }
  end

  describe 'associations' do
    it { should belong_to(:node) }
  end

  describe 'validations' do
    subject { build(:node_metric, valid_attributes) }

    it { should validate_presence_of(:collected_at) }
    it { should validate_presence_of(:cpu_usage_percent) }
    it { should validate_presence_of(:memory_total_mb) }
    it { should validate_presence_of(:memory_used_mb) }
    it { should validate_presence_of(:memory_available_mb) }
    it { should validate_presence_of(:uptime_seconds) }

    it { should validate_numericality_of(:cpu_usage_percent).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(100) }
    it { should validate_numericality_of(:memory_total_mb).is_greater_than(0) }
    it { should validate_numericality_of(:memory_used_mb).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:memory_available_mb).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:uptime_seconds).is_greater_than_or_equal_to(0) }
  end

  describe 'scopes' do
    let!(:old_metric) { create(:node_metric, node: node, collected_at: 2.hours.ago) }
    let!(:recent_metric) { create(:node_metric, node: node, collected_at: 1.hour.ago) }
    let!(:latest_metric) { create(:node_metric, node: node, collected_at: 30.minutes.ago) }

    describe '.recent' do
      it 'orders by collected_at descending' do
        expect(NodeMetric.recent).to eq([latest_metric, recent_metric, old_metric])
      end
    end

    describe '.for_node' do
      let(:other_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
      let!(:other_metric) { create(:node_metric, node: other_node) }

      it 'returns metrics for specific node only' do
        expect(NodeMetric.for_node(node.id)).to include(old_metric, recent_metric, latest_metric)
        expect(NodeMetric.for_node(node.id)).not_to include(other_metric)
      end
    end

    describe '.since' do
      it 'returns metrics since specified time' do
        expect(NodeMetric.since(90.minutes.ago)).to include(recent_metric, latest_metric)
        expect(NodeMetric.since(90.minutes.ago)).not_to include(old_metric)
      end
    end

    describe '.between' do
      it 'returns metrics between specified times' do
        expect(NodeMetric.between(2.5.hours.ago, 45.minutes.ago)).to include(old_metric, recent_metric)
        expect(NodeMetric.between(2.5.hours.ago, 45.minutes.ago)).not_to include(latest_metric)
      end
    end
  end

  describe 'class methods' do
    let!(:metric1) { create(:node_metric, node: node, cpu_usage_percent: 30, collected_at: 2.hours.ago) }
    let!(:metric2) { create(:node_metric, node: node, cpu_usage_percent: 50, collected_at: 1.hour.ago) }
    let!(:metric3) { create(:node_metric, node: node, cpu_usage_percent: 70, collected_at: 30.minutes.ago) }

    describe '.latest_for_node' do
      it 'returns the most recent metric for a node' do
        expect(NodeMetric.latest_for_node(node.id)).to eq(metric3)
      end
    end

    describe '.average_cpu_for_period' do
      it 'calculates average CPU usage for a period' do
        avg = NodeMetric.average_cpu_for_period(node.id, 3.hours.ago, Time.current)
        expect(avg).to eq(50.0) # (30 + 50 + 70) / 3
      end
    end

    describe '.max_memory_for_period' do
      let!(:memory_metric1) { create(:node_metric, node: node, memory_used_mb: 2048, collected_at: 2.hours.ago) }
      let!(:memory_metric2) { create(:node_metric, node: node, memory_used_mb: 4096, collected_at: 1.hour.ago) }
      let!(:memory_metric3) { create(:node_metric, node: node, memory_used_mb: 3072, collected_at: 30.minutes.ago) }

      it 'returns maximum memory usage for a period' do
        max_memory = NodeMetric.max_memory_for_period(node.id, 3.hours.ago, Time.current)
        expect(max_memory).to eq(4096)
      end
    end
  end

  describe 'calculated values' do
    subject { build(:node_metric, valid_attributes) }

    describe '#memory_usage_percent' do
      it 'calculates memory usage percentage' do
        expect(subject.memory_usage_percent).to eq(50.0) # 4096 / 8192 * 100
      end

      it 'returns 0 when total memory is 0' do
        subject.memory_total_mb = 0
        expect(subject.memory_usage_percent).to eq(0)
      end
    end

    describe '#swap_usage_percent' do
      it 'calculates swap usage percentage' do
        expect(subject.swap_usage_percent).to eq(25.0) # 512 / 2048 * 100
      end

      it 'returns 0 when swap total is nil' do
        subject.swap_total_mb = nil
        expect(subject.swap_usage_percent).to eq(0)
      end
    end

    describe '#memory_free_mb' do
      it 'calculates free memory' do
        expect(subject.memory_free_mb).to eq(4096) # 8192 - 4096
      end
    end

    describe '#swap_free_mb' do
      it 'calculates free swap' do
        expect(subject.swap_free_mb).to eq(1536) # 2048 - 512
      end
    end
  end

  describe 'load average accessors' do
    subject { build(:node_metric, valid_attributes) }

    it 'returns load average values' do
      expect(subject.load_1min).to eq(1.5)
      expect(subject.load_5min).to eq(1.2)
      expect(subject.load_15min).to eq(1.0)
    end
  end

  describe 'network statistics accessors' do
    subject { build(:node_metric, valid_attributes) }

    it 'returns network interfaces' do
      expect(subject.network_interfaces).to eq(['eth0'])
    end

    it 'returns network statistics for interface' do
      expect(subject.network_rx_bytes('eth0')).to eq(1024000)
      expect(subject.network_tx_bytes('eth0')).to eq(512000)
      expect(subject.network_rx_packets('eth0')).to eq(1000)
      expect(subject.network_tx_packets('eth0')).to eq(800)
    end

    it 'returns 0 for non-existent interface' do
      expect(subject.network_rx_bytes('eth1')).to eq(0)
    end
  end

  describe 'disk usage accessors' do
    subject { build(:node_metric, valid_attributes) }

    it 'returns disk mounts' do
      expect(subject.disk_mounts).to eq(['/'])
    end

    it 'returns disk usage statistics' do
      expect(subject.disk_usage_percent('/')).to eq(65.0)
      expect(subject.disk_total_gb('/')).to eq(100.0)
      expect(subject.disk_used_gb('/')).to eq(65.0)
      expect(subject.disk_available_gb('/')).to eq(35.0)
    end

    it 'returns 0 for non-existent mount' do
      expect(subject.disk_usage_percent('/tmp')).to eq(0)
    end
  end

  describe 'uptime helpers' do
    subject { build(:node_metric, uptime_seconds: 90061) } # 1 day, 1 hour, 1 minute, 1 second

    it 'calculates uptime in days' do
      expect(subject.uptime_days).to eq(1.0)
    end

    it 'calculates uptime in hours' do
      expect(subject.uptime_hours).to eq(25.0)
    end

    it 'formats uptime' do
      expect(subject.uptime_formatted).to eq('1d 1h 1m')
    end
  end

  describe 'health status indicators' do
    describe '#cpu_status' do
      it 'returns healthy for low CPU usage' do
        metric = build(:node_metric, cpu_usage_percent: 50)
        expect(metric.cpu_status).to eq('healthy')
      end

      it 'returns warning for moderate CPU usage' do
        metric = build(:node_metric, cpu_usage_percent: 75)
        expect(metric.cpu_status).to eq('warning')
      end

      it 'returns critical for high CPU usage' do
        metric = build(:node_metric, cpu_usage_percent: 90)
        expect(metric.cpu_status).to eq('critical')
      end
    end

    describe '#memory_status' do
      it 'returns healthy for low memory usage' do
        metric = build(:node_metric, memory_total_mb: 8192, memory_used_mb: 4096) # 50%
        expect(metric.memory_status).to eq('healthy')
      end

      it 'returns warning for moderate memory usage' do
        metric = build(:node_metric, memory_total_mb: 8192, memory_used_mb: 6554) # 80%
        expect(metric.memory_status).to eq('warning')
      end

      it 'returns critical for high memory usage' do
        metric = build(:node_metric, memory_total_mb: 8192, memory_used_mb: 7373) # 90%
        expect(metric.memory_status).to eq('critical')
      end
    end

    describe '#overall_health_status' do
      it 'returns critical if any metric is critical' do
        metric = build(:node_metric, 
          cpu_usage_percent: 90, # critical
          memory_total_mb: 8192, 
          memory_used_mb: 4096, # healthy
          disk_usage: { '/' => { 'usage_percent' => 50 } } # healthy
        )
        expect(metric.overall_health_status).to eq('critical')
      end

      it 'returns warning if any metric is warning and none critical' do
        metric = build(:node_metric, 
          cpu_usage_percent: 75, # warning
          memory_total_mb: 8192, 
          memory_used_mb: 4096, # healthy
          disk_usage: { '/' => { 'usage_percent' => 50 } } # healthy
        )
        expect(metric.overall_health_status).to eq('warning')
      end

      it 'returns healthy if all metrics are healthy' do
        metric = build(:node_metric, 
          cpu_usage_percent: 50, # healthy
          memory_total_mb: 8192, 
          memory_used_mb: 4096, # healthy
          disk_usage: { '/' => { 'usage_percent' => 50 } } # healthy
        )
        expect(metric.overall_health_status).to eq('healthy')
      end
    end
  end

  describe '#to_metrics_json' do
    subject { build(:node_metric, valid_attributes) }

    it 'returns properly formatted JSON' do
      json = subject.to_metrics_json
      
      expect(json).to include(:cpu, :memory, :swap, :disk, :network, :load_average, :uptime, :health_status)
      expect(json[:cpu]).to include(:usage_percent, :status)
      expect(json[:memory]).to include(:total_mb, :used_mb, :available_mb, :usage_percent, :status)
      expect(json[:uptime]).to include(:seconds, :formatted, :days)
    end
  end
end
