require 'rails_helper'

RSpec.describe DeploymentServices::PostgresqlDeploymentService, type: :service do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
  let(:parent_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, status: 'active') }
  let(:replica_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: parent_node) }
  let(:service) { DeploymentServices::PostgresqlDeploymentService.new(node) }
  let(:database_type_handler) { double('database_type_handler') }

  before do
    allow(node).to receive(:database_type_handler).and_return(database_type_handler)
    allow(service).to receive(:run_ansible_playbook)
  end

  describe '#deploy_primary!' do
    before do
      allow(database_type_handler).to receive(:primary_playbook).and_return('postgresql_primary.yml')
    end

    it 'runs the primary playbook with generated password' do
      expect(SecureRandom).to receive(:alphanumeric).with(32).and_return('generated_password')
      expect(service).to receive(:run_ansible_playbook).with(
        'postgresql_primary.yml',
        { postgres_password: 'generated_password' }
      )
      
      service.deploy_primary!
    end
  end

  describe '#deploy_replica!' do
    let(:replica_service) { DeploymentServices::PostgresqlDeploymentService.new(replica_node) }
    let(:primary_ip) { '192.168.1.100' }
    let(:replication_password) { 'repl_password' }

    before do
      allow(replica_node).to receive(:database_type_handler).and_return(database_type_handler)
      allow(database_type_handler).to receive(:replica_playbook).and_return('postgresql_replica.yml')
      allow(parent_node).to receive(:get_ip_address).and_return(primary_ip)
      allow(parent_node).to receive(:get_replication_password).and_return(replication_password)
      allow(replica_service).to receive(:run_ansible_playbook)
    end

    context 'with valid parent node' do
      it 'runs the replica playbook with primary connection details' do
        expect(replica_service).to receive(:run_ansible_playbook).with(
          'postgresql_replica.yml',
          {
            primary_ip: primary_ip,
            replication_password: replication_password,
            replica_node_name: replica_node.name.downcase.gsub(/[^a-z0-9]/, '-')
          }
        )
        
        replica_service.deploy_replica!
      end

      it 'sanitizes replica node name' do
        allow(replica_node).to receive(:name).and_return('Test Node #1')
        
        expect(replica_service).to receive(:run_ansible_playbook).with(
          'postgresql_replica.yml',
          hash_including(replica_node_name: 'test-node--1')
        )
        
        replica_service.deploy_replica!
      end
    end

    context 'without parent node' do
      let(:orphan_replica) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: nil) }
      let(:orphan_service) { DeploymentServices::PostgresqlDeploymentService.new(orphan_replica) }

      before do
        allow(orphan_replica).to receive(:database_type_handler).and_return(database_type_handler)
        allow(orphan_service).to receive(:run_ansible_playbook)
      end

      it 'returns false' do
        expect(orphan_service.deploy_replica!).to be false
      end

      it 'does not run ansible playbook' do
        expect(orphan_service).not_to receive(:run_ansible_playbook)
        orphan_service.deploy_replica!
      end
    end
  end

  describe '#configure_replication!' do
    before do
      allow(database_type_handler).to receive(:primary_replication_playbook).and_return('postgresql_configure_replication.yml')
      allow(node).to receive(:get_replication_password).and_return('repl_password')
      allow(node).to receive(:ensure_replication_password!)
    end

    context 'with primary node' do
      before do
        allow(node).to receive(:primary?).and_return(true)
      end

      it 'ensures replication password exists' do
        expect(node).to receive(:ensure_replication_password!)
        service.configure_replication!
      end

      it 'runs the primary replication playbook' do
        expect(service).to receive(:run_ansible_playbook).with(
          'postgresql_configure_replication.yml',
          { replication_password: 'repl_password' }
        )
        
        service.configure_replication!
      end
    end

    context 'with non-primary node' do
      before do
        allow(node).to receive(:primary?).and_return(false)
      end

      it 'returns false' do
        expect(service.configure_replication!).to be false
      end

      it 'does not run ansible playbook' do
        expect(service).not_to receive(:run_ansible_playbook)
        service.configure_replication!
      end
    end
  end

  describe '#cleanup_replication!' do
    before do
      allow(database_type_handler).to receive(:cleanup_playbook).and_return('postgresql_cleanup.yml')
    end

    it 'runs the cleanup playbook' do
      expect(service).to receive(:run_ansible_playbook).with('postgresql_cleanup.yml')
      service.cleanup_replication!
    end
  end

  describe '#create_user!' do
    before do
      allow(database_type_handler).to receive(:create_user_playbook).and_return('postgresql_create_user.yml')
    end

    it 'runs the create user playbook with default privileges' do
      expect(service).to receive(:run_ansible_playbook).with(
        'postgresql_create_user.yml',
        {
          username: 'testuser',
          password: 'testpass',
          privileges: 'ALL'
        }
      )
      
      service.create_user!('testuser', 'testpass')
    end

    it 'runs the create user playbook with custom privileges' do
      expect(service).to receive(:run_ansible_playbook).with(
        'postgresql_create_user.yml',
        {
          username: 'testuser',
          password: 'testpass',
          privileges: 'SELECT,INSERT'
        }
      )
      
      service.create_user!('testuser', 'testpass', 'SELECT,INSERT')
    end
  end

  describe '#destroy_user!' do
    before do
      allow(database_type_handler).to receive(:destroy_user_playbook).and_return('postgresql_destroy_user.yml')
    end

    it 'runs the destroy user playbook' do
      expect(service).to receive(:run_ansible_playbook).with(
        'postgresql_destroy_user.yml',
        { username: 'testuser' }
      )
      
      service.destroy_user!('testuser')
    end
  end

  describe '#backup_database' do
    it 'runs backup playbook with timestamp and default database' do
      timestamp = '20231201_143000'
      allow(Time).to receive(:current).and_return(Time.parse('2023-12-01 14:30:00'))
      allow(Time.current).to receive(:strftime).with("%Y%m%d_%H%M%S").and_return(timestamp)
      
      expect(service).to receive(:run_ansible_playbook).with(
        'backup_database.yml',
        {
          database_name: 'all',
          backup_file: "backup_#{node.id}_#{timestamp}.sql"
        }
      )
      
      service.backup_database
    end

    it 'runs backup playbook with specific database' do
      timestamp = '20231201_143000'
      allow(Time).to receive(:current).and_return(Time.parse('2023-12-01 14:30:00'))
      allow(Time.current).to receive(:strftime).with("%Y%m%d_%H%M%S").and_return(timestamp)
      
      expect(service).to receive(:run_ansible_playbook).with(
        'backup_database.yml',
        {
          database_name: 'myapp',
          backup_file: "backup_#{node.id}_#{timestamp}.sql"
        }
      )
      
      service.backup_database('myapp')
    end
  end

  describe '#restore_database' do
    it 'runs restore playbook' do
      expect(service).to receive(:run_ansible_playbook).with(
        'restore_database.yml',
        {
          database_name: 'myapp',
          backup_file: 'backup_123_20231201_143000.sql'
        }
      )
      
      service.restore_database('backup_123_20231201_143000.sql', 'myapp')
    end
  end

  describe '#check_replication_status' do
    context 'with replica node' do
      before do
        allow(node).to receive(:replica?).and_return(true)
      end

      it 'runs replica status check playbook' do
        expect(service).to receive(:run_ansible_playbook).with('check_replica_status.yml')
        service.check_replication_status
      end
    end

    context 'with primary node' do
      before do
        allow(node).to receive(:replica?).and_return(false)
      end

      it 'runs primary status check playbook' do
        expect(service).to receive(:run_ansible_playbook).with('check_primary_status.yml')
        service.check_replication_status
      end
    end
  end
end
