require 'rails_helper'

RSpec.describe MonitoringConfig, type: :model do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }

  describe 'associations' do
    it { should belong_to(:node) }
  end

  describe 'validations' do
    subject { build(:monitoring_config, node: node, config_type: 'cpu') }

    it { should validate_presence_of(:config_type) }
    it { should validate_inclusion_of(:config_type).in_array(%w[cpu memory disk network load_average]) }
    it { should validate_uniqueness_of(:config_type).scoped_to(:node_id) }
    it { should validate_presence_of(:thresholds) }
  end

  describe 'scopes' do
    let!(:enabled_config) { create(:monitoring_config, node: node, config_type: 'cpu', enabled: true) }
    let!(:disabled_config) { create(:monitoring_config, node: node, config_type: 'memory', enabled: false) }

    describe '.enabled' do
      it 'returns only enabled configurations' do
        expect(MonitoringConfig.enabled).to include(enabled_config)
        expect(MonitoringConfig.enabled).not_to include(disabled_config)
      end
    end

    describe '.for_type' do
      it 'returns configurations for specific type' do
        expect(MonitoringConfig.for_type('cpu')).to include(enabled_config)
        expect(MonitoringConfig.for_type('cpu')).not_to include(disabled_config)
      end
    end
  end

  describe 'class methods' do
    describe '.default_config_for_node' do
      it 'creates default configuration for node and type' do
        config = MonitoringConfig.default_config_for_node(node, 'cpu')
        
        expect(config.node).to eq(node)
        expect(config.config_type).to eq('cpu')
        expect(config.thresholds).to eq(MonitoringConfig::DEFAULT_THRESHOLDS['cpu'])
        expect(config.enabled).to be true
      end

      it 'returns existing configuration if already exists' do
        existing = create(:monitoring_config, node: node, config_type: 'cpu')
        config = MonitoringConfig.default_config_for_node(node, 'cpu')
        
        expect(config).to eq(existing)
      end
    end

    describe '.ensure_default_configs_for_node' do
      it 'creates all default configurations for a node' do
        expect {
          MonitoringConfig.ensure_default_configs_for_node(node)
        }.to change { node.monitoring_configs.count }.by(5) # cpu, memory, disk, network, load_average
      end

      it 'does not create duplicates if configurations already exist' do
        MonitoringConfig.ensure_default_configs_for_node(node)
        
        expect {
          MonitoringConfig.ensure_default_configs_for_node(node)
        }.not_to change { node.monitoring_configs.count }
      end
    end
  end

  describe 'instance methods' do
    let(:config) do
      create(:monitoring_config, 
        node: node, 
        config_type: 'cpu',
        thresholds: {
          'warning' => 70.0,
          'critical' => 85.0,
          'custom_warning' => 60.0,
          'custom_critical' => 80.0
        }
      )
    end

    describe '#warning_threshold' do
      it 'returns general warning threshold' do
        expect(config.warning_threshold).to eq(70.0)
      end

      it 'returns metric-specific warning threshold' do
        expect(config.warning_threshold('custom')).to eq(60.0)
      end

      it 'falls back to general threshold if metric-specific not found' do
        expect(config.warning_threshold('nonexistent')).to eq(70.0)
      end
    end

    describe '#critical_threshold' do
      it 'returns general critical threshold' do
        expect(config.critical_threshold).to eq(85.0)
      end

      it 'returns metric-specific critical threshold' do
        expect(config.critical_threshold('custom')).to eq(80.0)
      end

      it 'falls back to general threshold if metric-specific not found' do
        expect(config.critical_threshold('nonexistent')).to eq(85.0)
      end
    end

    describe '#check_threshold' do
      it 'returns healthy for values below warning threshold' do
        expect(config.check_threshold(50.0)).to eq('healthy')
      end

      it 'returns warning for values above warning but below critical' do
        expect(config.check_threshold(75.0)).to eq('warning')
      end

      it 'returns critical for values above critical threshold' do
        expect(config.check_threshold(90.0)).to eq('critical')
      end

      it 'returns unknown for disabled config' do
        config.update!(enabled: false)
        expect(config.check_threshold(90.0)).to eq('unknown')
      end

      it 'returns unknown for nil value' do
        expect(config.check_threshold(nil)).to eq('unknown')
      end

      it 'uses metric-specific thresholds when provided' do
        expect(config.check_threshold(65.0, 'custom')).to eq('warning') # above custom warning (60)
        expect(config.check_threshold(65.0)).to eq('healthy') # below general warning (70)
      end
    end

    describe '#update_threshold' do
      it 'updates general threshold' do
        config.update_threshold('warning', 75.0)
        expect(config.reload.thresholds['warning']).to eq(75.0)
      end

      it 'updates metric-specific threshold' do
        config.update_threshold('warning', 65.0, 'custom')
        expect(config.reload.thresholds['custom_warning']).to eq(65.0)
      end
    end
  end

  describe 'validation methods' do
    describe 'CPU threshold validation' do
      let(:cpu_config) { build(:monitoring_config, node: node, config_type: 'cpu') }

      it 'validates CPU warning threshold range' do
        cpu_config.thresholds = { 'warning' => 150.0 }
        expect(cpu_config).not_to be_valid
        expect(cpu_config.errors[:thresholds]).to include('CPU warning threshold must be between 0 and 100')
      end

      it 'validates CPU critical threshold range' do
        cpu_config.thresholds = { 'critical' => -10.0 }
        expect(cpu_config).not_to be_valid
        expect(cpu_config.errors[:thresholds]).to include('CPU critical threshold must be between 0 and 100')
      end

      it 'validates critical threshold is greater than warning' do
        cpu_config.thresholds = { 'warning' => 80.0, 'critical' => 70.0 }
        expect(cpu_config).not_to be_valid
        expect(cpu_config.errors[:thresholds]).to include('CPU critical threshold must be greater than warning threshold')
      end

      it 'is valid with proper thresholds' do
        cpu_config.thresholds = { 'warning' => 70.0, 'critical' => 85.0 }
        expect(cpu_config).to be_valid
      end
    end

    describe 'Memory threshold validation' do
      let(:memory_config) { build(:monitoring_config, node: node, config_type: 'memory') }

      it 'validates memory warning threshold range' do
        memory_config.thresholds = { 'warning' => 150.0 }
        expect(memory_config).not_to be_valid
        expect(memory_config.errors[:thresholds]).to include('Memory warning threshold must be between 0 and 100')
      end

      it 'validates memory critical threshold range' do
        memory_config.thresholds = { 'critical' => -10.0 }
        expect(memory_config).not_to be_valid
        expect(memory_config.errors[:thresholds]).to include('Memory critical threshold must be between 0 and 100')
      end

      it 'validates critical threshold is greater than warning' do
        memory_config.thresholds = { 'warning' => 90.0, 'critical' => 80.0 }
        expect(memory_config).not_to be_valid
        expect(memory_config.errors[:thresholds]).to include('Memory critical threshold must be greater than warning threshold')
      end

      it 'is valid with proper thresholds' do
        memory_config.thresholds = { 'warning' => 75.0, 'critical' => 90.0 }
        expect(memory_config).to be_valid
      end
    end

    describe 'Disk threshold validation' do
      let(:disk_config) { build(:monitoring_config, node: node, config_type: 'disk') }

      it 'validates disk warning threshold range' do
        disk_config.thresholds = { 'warning' => 150.0 }
        expect(disk_config).not_to be_valid
        expect(disk_config.errors[:thresholds]).to include('Disk warning threshold must be between 0 and 100')
      end

      it 'validates disk critical threshold range' do
        disk_config.thresholds = { 'critical' => -10.0 }
        expect(disk_config).not_to be_valid
        expect(disk_config.errors[:thresholds]).to include('Disk critical threshold must be between 0 and 100')
      end

      it 'validates critical threshold is greater than warning' do
        disk_config.thresholds = { 'warning' => 90.0, 'critical' => 80.0 }
        expect(disk_config).not_to be_valid
        expect(disk_config.errors[:thresholds]).to include('Disk critical threshold must be greater than warning threshold')
      end

      it 'is valid with proper thresholds' do
        disk_config.thresholds = { 'warning' => 80.0, 'critical' => 90.0 }
        expect(disk_config).to be_valid
      end
    end
  end

  describe 'default thresholds' do
    it 'has proper default thresholds for all config types' do
      expect(MonitoringConfig::DEFAULT_THRESHOLDS).to include('cpu', 'memory', 'disk', 'load_average', 'network')
      
      # CPU thresholds
      expect(MonitoringConfig::DEFAULT_THRESHOLDS['cpu']).to eq({
        'warning' => 70.0,
        'critical' => 85.0
      })
      
      # Memory thresholds
      expect(MonitoringConfig::DEFAULT_THRESHOLDS['memory']).to eq({
        'warning' => 75.0,
        'critical' => 90.0
      })
      
      # Disk thresholds
      expect(MonitoringConfig::DEFAULT_THRESHOLDS['disk']).to eq({
        'warning' => 80.0,
        'critical' => 90.0
      })
    end
  end
end
