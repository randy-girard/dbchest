require 'rails_helper'

RSpec.describe DeploymentServices::CassandraDeploymentService, type: :service do
  let(:database_type) { create(:database_type, slug: 'cassandra') }
  let(:database_type_version) { create(:database_type_version, database_type: database_type, version: '4.0') }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:primary_node) { create(:node, cluster: cluster, database_type_version: database_type_version) }
  let(:replica_node) { create(:node, cluster: cluster, database_type_version: database_type_version, parent_node: primary_node) }

  let(:service) { described_class.new(primary_node) }
  let(:replica_service) { described_class.new(replica_node) }

  before do
    allow_any_instance_of(DeploymentServices::BaseDeploymentService).to receive(:run_ansible_playbook).and_return(true)
    allow(primary_node).to receive(:get_ip_address).and_return('192.168.1.10')
    allow(replica_node).to receive(:get_ip_address).and_return('192.168.1.11')
  end

  describe '#deploy_primary!' do
    it 'runs the Cassandra primary deployment playbook' do
      expect(service).to receive(:run_ansible_playbook).with(
        'create_node.yml',
        hash_including(
          cluster_name: anything,
          seeds: anything,
          listen_address: '192.168.1.10',
          replication_factor: 1
        )
      )

      service.deploy_primary!
    end

    it 'generates a cluster name based on cluster' do
      cluster.update(name: 'Test Cluster-123')
      expected_name = 'test_cluster_123_cluster'

      expect(service).to receive(:run_ansible_playbook).with(
        'create_node.yml',
        hash_including(cluster_name: expected_name)
      )

      service.deploy_primary!
    end
  end

  describe '#deploy_replica!' do
    it 'runs the Cassandra replica deployment playbook' do
      expect(replica_service).to receive(:run_ansible_playbook).with(
        'add_node.yml',
        hash_including(
          cluster_name: anything,
          seeds: anything,
          listen_address: '192.168.1.11',
          primary_ip: '192.168.1.10',
          replication_factor: 1
        )
      )

      replica_service.deploy_replica!
    end

    it 'returns false if no primary node exists' do
      replica_node.update(parent_node: nil)
      expect(replica_service.deploy_replica!).to be false
    end
  end

  describe '#configure_replication!' do
    let!(:additional_node) { create(:node, cluster: cluster, database_type_version: database_type_version, parent_node: primary_node, status: 'active') }

    before do
      allow(additional_node).to receive(:get_ip_address).and_return('192.168.1.12')
      mock_replicas = double('replicas_relation')
      allow(mock_replicas).to receive(:where).with(status: "active").and_return([additional_node])
      allow(primary_node).to receive(:replicas).and_return(mock_replicas)
    end

    it 'configures replication for all active additional nodes' do
      expect(service).to receive(:run_ansible_playbook).with(
        'expand_cluster.yml',
        hash_including(
          cluster_name: anything,
          new_node_ip: '192.168.1.12',
          seeds: anything,
          replication_factor: anything
        )
      )

      service.configure_replication!
    end

    it 'returns true when no additional nodes exist' do
      mock_empty_replicas = double('replicas_relation')
      allow(mock_empty_replicas).to receive(:where).with(status: "active").and_return([])
      allow(primary_node).to receive(:replicas).and_return(mock_empty_replicas)
      expect(service.configure_replication!).to be true
    end

    it 'returns false for replica nodes' do
      expect(replica_service.configure_replication!).to be false
    end
  end

  describe '#cleanup_replication!' do
    it 'runs the cleanup playbook for replica nodes' do
      expect(replica_service).to receive(:run_ansible_playbook).with(
        'remove_node.yml',
        hash_including(
          cluster_name: anything,
          node_ip: '192.168.1.11',
          seeds: anything
        )
      )

      replica_service.cleanup_replication!
    end

    it 'returns false for primary nodes' do
      expect(service.cleanup_replication!).to be false
    end

    it 'returns false if no primary node exists' do
      replica_node.update(parent_node: nil)
      expect(replica_service.cleanup_replication!).to be false
    end
  end

  describe '#create_user!' do
    it 'runs the create user playbook with correct parameters' do
      expect(service).to receive(:run_ansible_playbook).with(
        'create_user.yml',
        {
          username: 'testuser',
          password: 'testpass',
          privileges: ['LOGIN'],
          superuser: false
        }
      )

      service.create_user!('testuser', 'testpass', ['LOGIN'])
    end

    it 'uses default privileges when none provided' do
      expect(service).to receive(:run_ansible_playbook).with(
        'create_user.yml',
        hash_including(privileges: ['LOGIN'])
      )

      service.create_user!('testuser', 'testpass')
    end

    it 'sets superuser flag when SUPERUSER privilege is included' do
      expect(service).to receive(:run_ansible_playbook).with(
        'create_user.yml',
        hash_including(superuser: true)
      )

      service.create_user!('testuser', 'testpass', ['SUPERUSER', 'LOGIN'])
    end
  end

  describe '#destroy_user!' do
    it 'runs the destroy user playbook' do
      expect(service).to receive(:run_ansible_playbook).with(
        'destroy_user.yml',
        {
          username: 'testuser'
        }
      )

      service.destroy_user!('testuser')
    end
  end

  describe '#create_keyspace!' do
    it 'runs the create keyspace playbook' do
      expect(service).to receive(:run_ansible_playbook).with(
        'create_keyspace.yml',
        {
          keyspace_name: 'testkeyspace',
          replication_factor: 3,
          cluster_name: anything
        }
      )

      service.create_keyspace!('testkeyspace')
    end

    it 'uses custom replication factor when provided' do
      expect(service).to receive(:run_ansible_playbook).with(
        'create_keyspace.yml',
        hash_including(replication_factor: 3)
      )

      service.create_keyspace!('testkeyspace', 3)
    end
  end

  describe '#drop_keyspace!' do
    it 'runs the drop keyspace playbook' do
      expect(service).to receive(:run_ansible_playbook).with(
        'drop_keyspace.yml',
        {
          keyspace_name: 'testkeyspace'
        }
      )

      service.drop_keyspace!('testkeyspace')
    end
  end

  describe '#backup_keyspace' do
    it 'runs the backup playbook with timestamp' do
      allow(Time).to receive(:current).and_return(Time.parse("2023-01-01 12:00:00"))

      expect(service).to receive(:run_ansible_playbook).with(
        'backup_keyspace.yml',
        hash_including(
          keyspace_name: 'testkeyspace',
          snapshot_name: "backup_#{primary_node.id}_20230101_120000",
          backup_path: '/var/backups/cassandra'
        )
      )

      service.backup_keyspace('testkeyspace')
    end
  end

  describe '#restore_keyspace' do
    it 'runs the restore playbook' do
      expect(service).to receive(:run_ansible_playbook).with(
        'restore_keyspace.yml',
        {
          keyspace_name: 'testkeyspace',
          snapshot_name: 'test_snapshot',
          backup_path: '/var/backups/cassandra'
        }
      )

      service.restore_keyspace('testkeyspace', 'test_snapshot')
    end
  end

  describe '#check_cluster_status' do
    it 'runs the cluster status check playbook' do
      expect(service).to receive(:run_ansible_playbook).with(
        'check_cluster_status.yml',
        hash_including(cluster_name: anything)
      )

      service.check_cluster_status
    end
  end

  describe '#repair_keyspace' do
    it 'runs the repair playbook for specific keyspace' do
      expect(service).to receive(:run_ansible_playbook).with(
        'repair_keyspace.yml',
        {
          keyspace_name: 'testkeyspace'
        }
      )

      service.repair_keyspace('testkeyspace')
    end

    it 'runs the repair playbook for all keyspaces when none specified' do
      expect(service).to receive(:run_ansible_playbook).with(
        'repair_keyspace.yml',
        {
          keyspace_name: nil
        }
      )

      service.repair_keyspace
    end
  end

  describe '#scale_cluster' do
    let!(:node2) { create(:node, cluster: cluster, database_type_version: database_type_version, status: 'active') }
    let!(:node3) { create(:node, cluster: cluster, database_type_version: database_type_version, status: 'active') }

    it 'scales up the cluster when target size is larger' do
      expect(service).to receive(:run_ansible_playbook).with(
        'add_node.yml',
        hash_including(
          cluster_name: anything,
          seeds: anything,
          replication_factor: anything
        )
      ).exactly(3).times

      service.scale_cluster(5) # Current: 2, Target: 5, so add 3
    end

    it 'scales down the cluster when target size is smaller' do
      expect(service).to receive(:remove_node_from_cluster).once

      service.scale_cluster(1) # Current: 2, Target: 1, so remove 1
    end

    it 'does nothing when target size equals current size' do
      expect(service).not_to receive(:run_ansible_playbook)
      expect(service).not_to receive(:remove_node_from_cluster)

      result = service.scale_cluster(2) # Current: 2, Target: 2
      expect(result).to be true
    end
  end

  describe 'private methods' do
    describe '#cluster_name' do
      it 'generates a valid cluster name from cluster name' do
        cluster.update(name: 'Test Cluster-123')
        expected_name = 'test_cluster_123_cluster'
        expect(service.send(:cluster_name)).to eq(expected_name)
      end
    end

    describe '#seeds_list' do
      let!(:node2) { create(:node, cluster: cluster, database_type_version: database_type_version, status: 'active') }
      let!(:node3) { create(:node, cluster: cluster, database_type_version: database_type_version, status: 'active') }

      before do
        primary_node.update!(status: 'active')
        allow(primary_node).to receive(:get_ip_address).and_return('192.168.1.10')
        allow(node2).to receive(:get_ip_address).and_return('192.168.1.12')
        allow(node3).to receive(:get_ip_address).and_return('192.168.1.13')

        # Mock cluster_nodes to return the test nodes
        mock_cluster_nodes = double('cluster_nodes_relation')
        allow(mock_cluster_nodes).to receive(:limit).with(3).and_return([primary_node, node2, node3])
        allow(service).to receive(:cluster_nodes).and_return(mock_cluster_nodes)
      end

      it 'returns comma-separated list of first 3 node IPs' do
        seeds = service.send(:seeds_list)
        expect(seeds.split(',').length).to be <= 3
        expect(seeds).to include('192.168.1.10')
      end
    end

    describe '#calculate_replication_factor' do
      it 'returns 3 for single node cluster' do
        expect(service.send(:calculate_replication_factor)).to eq(3)
      end

      it 'returns 1 for 2-3 node cluster' do
        # Create a new isolated cluster for this test
        isolated_cluster = create(:cluster, database_type: database_type)
        isolated_node = create(:node, cluster: isolated_cluster, database_type_version: database_type_version, status: 'active')
        isolated_service = described_class.new(isolated_node)
        expect(isolated_service.send(:calculate_replication_factor)).to eq(1)
      end

      it 'returns 2 for 4-6 node cluster' do
        # Create a new isolated cluster for this test
        isolated_cluster = create(:cluster, database_type: database_type)
        2.times { create(:node, cluster: isolated_cluster, database_type_version: database_type_version, status: 'active') }
        isolated_node = create(:node, cluster: isolated_cluster, database_type_version: database_type_version, status: 'active')
        isolated_service = described_class.new(isolated_node)
        expect(isolated_service.send(:calculate_replication_factor)).to eq(2)
      end

      it 'returns 3 for larger clusters' do
        10.times { create(:node, cluster: cluster, database_type_version: database_type_version, status: 'active') }
        expect(service.send(:calculate_replication_factor)).to eq(3)
      end
    end
  end
end
