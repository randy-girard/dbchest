require 'rails_helper'

RSpec.describe DeploymentServices::MongodbDeploymentService, type: :service do
  let(:database_type) { create(:database_type, slug: 'mongodb') }
  let(:database_type_version) { create(:database_type_version, database_type: database_type, version: '7.0') }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:primary_node) { create(:node, cluster: cluster, database_type_version: database_type_version) }
  let(:replica_node) { create(:node, cluster: cluster, database_type_version: database_type_version, parent_node: primary_node) }

  let(:service) { described_class.new(primary_node) }
  let(:replica_service) { described_class.new(replica_node) }

  before do
    allow_any_instance_of(DeploymentServices::BaseDeploymentService).to receive(:run_ansible_playbook).and_return(true)
  end

  describe '#deploy_primary!' do
    it 'runs the MongoDB primary deployment playbook' do
      expect(service).to receive(:run_ansible_playbook).with(
        'create_node.yml',
        hash_including(
          replica_set_name: anything,
          mongodb_root_password: anything
        )
      )

      service.deploy_primary!
    end

    it 'generates a replica set name based on cluster' do
      expect(service).to receive(:run_ansible_playbook).with(
        'create_node.yml',
        hash_including(replica_set_name: "#{cluster.name.downcase.gsub(/[^a-z0-9]/, '_')}_rs")
      )

      service.deploy_primary!
    end
  end

  describe '#deploy_replica!' do
    it 'runs the MongoDB replica deployment playbook' do
      expect(replica_service).to receive(:run_ansible_playbook).with(
        'configure_replica.yml',
        hash_including(
          replica_set_name: anything,
          primary_ip: primary_node.get_ip_address,
          mongodb_root_password: anything
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
    let!(:additional_replica) { create(:node, cluster: cluster, database_type_version: database_type_version, parent_node: primary_node, status: 'active') }

    it 'configures replication for all active replicas' do
      expect(service).to receive(:run_ansible_playbook).with(
        'configure_primary_replication.yml',
        hash_including(
          replica_set_name: anything,
          replica_ip: additional_replica.get_ip_address
        )
      )

      service.configure_replication!
    end

    it 'returns true when no replicas exist' do
      primary_node.replicas.destroy_all
      expect(service.configure_replication!).to be true
    end

    it 'returns false for replica nodes' do
      expect(replica_service.configure_replication!).to be false
    end
  end

  describe '#cleanup_replication!' do
    it 'runs the cleanup playbook for replica nodes' do
      expect(replica_service).to receive(:run_ansible_playbook).with(
        'cleanup_replica_config.yml',
        hash_including(
          replica_set_name: anything,
          replica_ip: replica_node.get_ip_address,
          mongodb_root_password: anything
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
          database: 'admin',
          privileges: [ 'readWrite' ],
          mongodb_root_password: anything
        }
      )

      service.create_user!('testuser', 'testpass', [ 'readWrite' ])
    end

    it 'uses default roles when none provided' do
      expect(service).to receive(:run_ansible_playbook).with(
        'create_user.yml',
        hash_including(privileges: [ 'readWrite' ])
      )

      service.create_user!('testuser', 'testpass')
    end
  end

  describe '#destroy_user!' do
    it 'runs the destroy user playbook' do
      expect(service).to receive(:run_ansible_playbook).with(
        'destroy_user.yml',
        {
          username: 'testuser',
          database: 'admin',
          mongodb_root_password: anything
        }
      )

      service.destroy_user!('testuser')
    end
  end



  describe '#backup_database' do
    it 'runs the backup playbook with timestamp' do
      allow(Time).to receive(:current).and_return(Time.parse("2023-01-01 12:00:00"))

      expect(service).to receive(:run_ansible_playbook).with(
        'backup_database.yml',
        hash_including(
          database_name: 'testdb',
          backup_file: "mongodb_backup_#{primary_node.id}_20230101_120000",
          mongodb_root_password: anything
        )
      )

      service.backup_database('testdb')
    end

    it 'uses "all" as default database name' do
      expect(service).to receive(:run_ansible_playbook).with(
        'backup_database.yml',
        hash_including(database_name: 'all')
      )

      service.backup_database
    end
  end

  describe '#restore_database' do
    it 'runs the restore playbook' do
      expect(service).to receive(:run_ansible_playbook).with(
        'restore_database.yml',
        {
          database_name: 'testdb',
          backup_file: 'backup_file.gz',
          mongodb_root_password: anything
        }
      )

      service.restore_database('backup_file.gz', 'testdb')
    end
  end

  describe '#check_replication_status' do
    context 'for primary node' do
      it 'runs the primary status check playbook' do
        expect(service).to receive(:run_ansible_playbook).with(
          'check_primary_status.yml',
          hash_including(mongodb_root_password: anything)
        )

        service.check_replication_status
      end
    end

    context 'for replica node' do
      it 'runs the replica status check playbook' do
        expect(replica_service).to receive(:run_ansible_playbook).with(
          'check_replica_status.yml',
          hash_including(mongodb_root_password: anything)
        )

        replica_service.check_replication_status
      end
    end
  end

  describe '#get_replica_set_status' do
    it 'runs the replica set status playbook' do
      expect(service).to receive(:run_ansible_playbook).with(
        'get_replica_set_status.yml',
        hash_including(
          mongodb_root_password: anything,
          replica_set_name: anything
        )
      )

      service.get_replica_set_status
    end
  end

  describe 'private methods' do
    describe '#replica_set_name' do
      it 'generates a valid replica set name from cluster name' do
        cluster.update(name: 'Test Cluster-123')
        expected_name = 'test_cluster_123_rs'
        expect(service.send(:replica_set_name)).to eq(expected_name)
      end
    end
  end
end
