require 'rails_helper'

RSpec.describe Node, type: :model do
  let(:database_type) { create(:database_type, :with_versions) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:database_type_version) { database_type.database_type_versions.first }
  let(:node) { build(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }

  describe 'associations' do
    it { should belong_to(:cluster) }
    it { should belong_to(:provider) }
    it { should belong_to(:database_type_version) }
    it { should belong_to(:parent_node).class_name('Node').optional }
    it { should have_many(:credentials).dependent(:destroy) }
    it { should have_many(:node_settings).dependent(:destroy) }
    it { should have_many(:node_metrics).dependent(:destroy) }
    it { should have_many(:monitoring_configs).dependent(:destroy) }
    it { should have_many(:replicas).class_name('Node').with_foreign_key('parent_node_id').dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }

    it 'validates name uniqueness within cluster' do
      create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, name: 'test-node')
      duplicate_node = build(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, name: 'test-node')

      expect(duplicate_node).not_to be_valid
      expect(duplicate_node.errors[:name]).to include('has already been taken')
    end

    it 'allows same name in different clusters' do
      other_cluster = create(:cluster, database_type: database_type)
      create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, name: 'test-node')
      other_node = build(:node, cluster: other_cluster, provider: provider, database_type_version: database_type_version, name: 'test-node')

      expect(other_node).to be_valid
    end

    it 'validates status inclusion' do
      node.status = 'invalid_status'
      expect(node).not_to be_valid
      expect(node.errors[:status]).to include('is not included in the list')
    end
  end

  describe 'nested attributes' do
    it { should accept_nested_attributes_for(:node_settings) }
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'sets default status to pending' do
        node.status = nil
        node.valid?
        expect(node.status).to eq('pending')
      end

      it 'sets default database_type_version from cluster' do
        node.database_type_version = nil
        node.valid?
        expect(node.database_type_version).to eq(cluster.default_version)
      end

      context 'for replica nodes' do
        let(:parent_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
        let(:replica) { build(:node, cluster: cluster, provider: provider, parent_node: parent_node, database_type_version: nil) }

        it 'sets database_type_version to match parent node' do
          replica.valid?
          expect(replica.database_type_version).to eq(parent_node.database_type_version)
        end
      end
    end

    describe 'after_create' do
      it 'calls ensure_ssh_keys_and_password' do
        expect(node).to receive(:ensure_ssh_keys_and_password)
        node.save!
      end

      it 'calls broadcast_initial_status' do
        expect(node).to receive(:broadcast_initial_status)
        node.save!
      end
    end

    describe 'after_update' do
      it 'calls broadcast_status_change when status changes' do
        node.save!
        expect(node).to receive(:broadcast_status_change)
        node.update!(status: 'active')
      end

      it 'does not call broadcast_status_change when status does not change' do
        node.save!
        expect(node).not_to receive(:broadcast_status_change)
        node.update!(name: 'new-name')
      end
    end
  end

  describe 'custom validations' do
    describe 'parent_node_must_be_primary' do
      let(:primary_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
      let(:replica_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: primary_node) }

      it 'allows replica of primary node' do
        new_replica = build(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: primary_node)
        expect(new_replica).to be_valid
      end

      it 'does not allow replica of replica node' do
        replica_of_replica = build(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: replica_node)
        expect(replica_of_replica).not_to be_valid
        expect(replica_of_replica.errors[:parent_node]).to include('cannot be a replica node. Replicas can only be created from primary nodes.')
      end
    end

    describe 'database_type_version_matches_cluster' do
      let(:other_database_type) { create(:database_type, :mysql, :with_versions) }
      let(:mysql_version) { other_database_type.database_type_versions.first }

      it 'allows matching database type' do
        expect(node).to be_valid
      end

      it 'does not allow mismatched database type' do
        node.database_type_version = mysql_version
        expect(node).not_to be_valid
        expect(node.errors[:database_type_version]).to include(match(/must match the cluster's database type/))
      end
    end

    describe 'replica_version_matches_primary' do
      let(:primary_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
      let(:other_version) { create(:database_type_version, database_type: database_type, version: '16.0') }

      it 'allows replica with same version as primary' do
        replica = build(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: primary_node)
        expect(replica).to be_valid
      end

      it 'does not allow replica with different version than primary' do
        replica = build(:node, cluster: cluster, provider: provider, database_type_version: other_version, parent_node: primary_node)
        expect(replica).not_to be_valid
        expect(replica.errors[:database_type_version]).to include(match(/must match the primary node's version/))
      end
    end
  end

  describe 'instance methods' do
    before { node.save! }

    describe '#primary?' do
      it 'returns true when parent_node_id is nil' do
        expect(node.primary?).to be true
      end

      it 'returns false when parent_node_id is present' do
        parent_node = create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version)
        replica = create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: parent_node)
        expect(replica.primary?).to be false
      end
    end

    describe '#replica?' do
      it 'returns false when parent_node_id is nil' do
        expect(node.replica?).to be false
      end

      it 'returns true when parent_node_id is present' do
        parent_node = create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version)
        replica = create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: parent_node)
        expect(replica.replica?).to be true
      end
    end

    describe '#active?' do
      it 'returns true when status is active' do
        node.update!(status: 'active')
        expect(node.active?).to be true
      end

      it 'returns false when status is not active' do
        node.update!(status: 'pending')
        expect(node.active?).to be false
      end
    end

    describe '#has_replicas?' do
      it 'returns false when no replicas exist' do
        expect(node.has_replicas?).to be false
      end

      it 'returns true when replicas exist' do
        create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: node)
        expect(node.has_replicas?).to be true
      end
    end

    describe '#can_create_replicas?' do
      it 'returns true when node is primary and active' do
        node.update!(status: 'active')
        expect(node.can_create_replicas?).to be true
      end

      it 'returns false when node is not active' do
        node.update!(status: 'pending')
        expect(node.can_create_replicas?).to be false
      end

      it 'returns false when node is replica' do
        parent_node = create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, status: 'active')
        replica = create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: parent_node, status: 'active')
        expect(replica.can_create_replicas?).to be false
      end
    end

    describe '#database_version' do
      it 'returns database_type_version version' do
        expect(node.database_version).to eq(database_type_version.version)
      end

      it 'returns nil when database_type_version is nil' do
        node.database_type_version = nil
        expect(node.database_version).to be_nil
      end
    end

    describe '#database_type_slug' do
      it 'returns database type slug' do
        expect(node.database_type_slug).to eq(database_type.slug)
      end
    end

    describe '#database_type_name' do
      it 'returns database type name' do
        expect(node.database_type_name).to eq(database_type.name)
      end
    end

    describe '#status_display' do
      it 'returns human readable status' do
        node.update!(status: 'active')
        expect(node.status_display).to eq('Active')
      end

      it 'returns humanized status for unknown status' do
        allow(node).to receive(:status).and_return('custom_status')
        expect(node.status_display).to eq('Custom status')
      end
    end

    describe '#status_badge_class' do
      it 'returns correct CSS class for active status' do
        node.update!(status: 'active')
        expect(node.status_badge_class).to eq('bg-success')
      end

      it 'returns correct CSS class for error status' do
        node.update!(status: 'error')
        expect(node.status_badge_class).to eq('bg-danger')
      end

      it 'returns default CSS class for unknown status' do
        allow(node).to receive(:status).and_return('unknown')
        expect(node.status_badge_class).to eq('bg-primary')
      end
    end

    describe '#update_status!' do
      it 'updates the status' do
        expect { node.update_status!('active', 'Node is now active') }
          .to change { node.reload.status }.from('pending').to('active')
      end

      it 'calls broadcast_status_update' do
        expect(node).to receive(:broadcast_status_update).at_least(:once)
        node.update_status!('active', 'Test message')
      end
    end

    describe '#ensure_replication_password!' do
      it 'generates password when blank' do
        node.replication_password = nil
        password = node.ensure_replication_password!
        expect(password).to be_present
        expect(node.reload.replication_password).to eq(password)
      end

      it 'returns existing password when present' do
        existing_password = 'existing_password'
        node.update!(replication_password: existing_password)
        password = node.ensure_replication_password!
        expect(password).to eq(existing_password)
      end
    end

    describe '#get_replication_password' do
      context 'for primary node' do
        it 'returns own replication password' do
          expect(node).to receive(:ensure_replication_password!).and_return('primary_password')
          expect(node.get_replication_password).to eq('primary_password')
        end
      end

      context 'for replica node' do
        let(:parent_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
        let(:replica) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: parent_node) }

        it 'returns parent node replication password' do
          expect(parent_node).to receive(:ensure_replication_password!).and_return('parent_password')
          expect(replica.get_replication_password).to eq('parent_password')
        end
      end
    end

    describe '#get_ip_address' do
      context 'when ip_address is in runtime_config' do
        it 'returns the IP address without subnet' do
          node.runtime_config = { 'ip_address' => '192.168.1.100/24' }
          expect(node.get_ip_address).to eq('192.168.1.100')
        end

        it 'returns the IP address when already clean' do
          node.runtime_config = { 'ip_address' => '192.168.1.100' }
          expect(node.get_ip_address).to eq('192.168.1.100')
        end
      end

      context 'when ip_address is not in runtime_config' do
        it 'checks alternative keys' do
          node.runtime_config = { 'public_ip' => '10.0.0.1' }
          expect(node.get_ip_address).to eq('10.0.0.1')
        end

        it 'checks network interfaces' do
          node.runtime_config = {
            'network_interfaces' => [
              { 'ip' => '172.16.0.1/16' },
              { 'ip' => '192.168.1.100/24' }
            ]
          }
          expect(node.get_ip_address).to eq('172.16.0.1')
        end

        it 'returns nil when no IP found' do
          node.runtime_config = {}
          expect(node.get_ip_address).to be_nil
        end
      end

      context 'with invalid IP addresses' do
        it 'handles invalid IP gracefully' do
          node.runtime_config = { 'ip_address' => 'invalid-ip' }
          expect(node.get_ip_address).to eq('invalid-ip')
        end

        it 'attempts hostname resolution' do
          node.runtime_config = { 'ip_address' => 'localhost' }
          allow(Resolv).to receive(:getaddress).with('localhost').and_return('127.0.0.1')
          expect(node.get_ip_address).to eq('127.0.0.1')
        end

        it 'handles hostname resolution failure' do
          node.runtime_config = { 'ip_address' => 'nonexistent.host' }
          allow(Resolv).to receive(:getaddress).and_raise(Resolv::ResolvError.new('Name not found'))
          expect(node.get_ip_address).to eq('nonexistent.host')
        end
      end
    end

    describe '#replication_method_for' do
      let(:target_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }

      it 'returns nil for non-Node objects' do
        expect(node.replication_method_for('not a node')).to be_nil
      end

      it 'returns nil when target node has no database_type_version' do
        target_node.database_type_version = nil
        expect(node.replication_method_for(target_node)).to be_nil
      end

      it 'returns nil when database types do not match' do
        other_db_type = create(:database_type, name: 'MySQL')
        other_version = create(:database_type_version, database_type: other_db_type)
        target_node.database_type_version = other_version
        expect(node.replication_method_for(target_node)).to be_nil
      end

      it 'delegates to database_type_version for compatible types' do
        expect(database_type_version).to receive(:replication_method_for_cross_version).with(target_node.database_type_version)
        node.replication_method_for(target_node)
      end
    end

    describe '#provision_replica!' do
      let(:parent_node) { create(:node, :active, cluster: cluster, provider: provider, database_type_version: database_type_version) }
      let(:replica) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: parent_node) }

      it 'returns false when no parent node' do
        expect(node.provision_replica!).to be false
      end

      it 'returns false when parent node is not active' do
        parent_node.update!(status: 'pending')
        expect(replica.provision_replica!).to be false
      end

      it 'calls CreateService when parent is active' do
        expect(CreateService).to receive(:perform_async).with(replica.id, true)
        replica.provision_replica!
      end
    end

    describe '#broadcast_status_update' do
      before { node.save! }

      it 'broadcasts to multiple channels' do
        expect(ActionCable.server).to receive(:broadcast).at_least(3).times
        node.send(:broadcast_status_update, 'Test message')
      end

      it 'includes node data in broadcast' do
        expect(ActionCable.server).to receive(:broadcast) do |channel, data|
          expect(data[:id]).to eq(node.id)
          expect(data[:status]).to eq(node.status)
          expect(data[:name]).to eq(node.name)
        end.at_least(:once)

        node.send(:broadcast_status_update, 'Test message')
      end

      it 'handles broadcast errors gracefully' do
        allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError.new('Broadcast failed'))
        expect { node.send(:broadcast_status_update) }.not_to raise_error
      end
    end
  end

  describe 'factory' do
    it 'creates a valid node' do
      expect(node).to be_valid
    end

    it 'creates primary node with trait' do
      primary = build(:node, :primary, cluster: cluster, provider: provider, database_type_version: database_type_version)
      expect(primary.parent_node).to be_nil
    end

    it 'creates replica node with trait' do
      replica = build(:node, :replica, cluster: cluster, provider: provider, database_type_version: database_type_version)
      expect(replica.parent_node).to be_present
    end

    it 'creates active node with trait' do
      active_node = build(:node, :active, cluster: cluster, provider: provider, database_type_version: database_type_version)
      expect(active_node.status).to eq('active')
    end
  end

  describe 'dependent destroy' do
    let(:test_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }

    before do
      # Clear any default monitoring configs that might be created
      test_node.monitoring_configs.destroy_all
    end

    it 'destroys associated node_metrics when node is destroyed' do
      # Create some metrics for the node
      create(:node_metric, node: test_node)
      create(:node_metric, node: test_node)

      expect {
        test_node.destroy
      }.to change { NodeMetric.count }.by(-2)
    end

    it 'destroys associated monitoring_configs when node is destroyed' do
      # Create some monitoring configs for the node (after clearing defaults)
      MonitoringConfig.create!(node: test_node, config_type: 'cpu', thresholds: { warning: 70, critical: 85 })
      MonitoringConfig.create!(node: test_node, config_type: 'memory', thresholds: { warning: 75, critical: 90 })

      expect {
        test_node.destroy
      }.to change { MonitoringConfig.count }.by(-2)
    end

    it 'destroys associated credentials when node is destroyed' do
      # Create some credentials for the node
      create(:credential, node: test_node)

      expect {
        test_node.destroy
      }.to change { Credential.count }.by(-1)
    end

    it 'destroys associated node_settings when node is destroyed' do
      # Node settings are created automatically, just verify they're destroyed
      initial_count = test_node.node_settings.count

      expect {
        test_node.destroy
      }.to change { NodeSetting.count }.by(-initial_count)
    end

    it 'destroys all associated records when node is destroyed' do
      # Create all types of associated records
      create(:node_metric, node: test_node)
      MonitoringConfig.create!(node: test_node, config_type: 'cpu', thresholds: { warning: 70, critical: 85 })
      create(:credential, node: test_node)
      initial_settings_count = test_node.node_settings.count

      expect {
        test_node.destroy
      }.to change { NodeMetric.count }.by(-1)
        .and change { MonitoringConfig.count }.by(-1)
        .and change { Credential.count }.by(-1)
        .and change { NodeSetting.count }.by(-initial_settings_count)
    end
  end
end
