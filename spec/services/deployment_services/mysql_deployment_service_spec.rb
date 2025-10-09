require 'rails_helper'

RSpec.describe DeploymentServices::MysqlDeploymentService, type: :service do
  let(:database_type) { create(:database_type, slug: 'mysql') }
  let(:database_type_version) { create(:database_type_version, database_type: database_type, version: '8.0') }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
  let(:parent_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, status: 'active') }
  let(:replica_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: parent_node) }
  let(:service) { DeploymentServices::MysqlDeploymentService.new(node) }
  let(:database_type_handler) { double('database_type_handler') }

  before do
    allow(node).to receive(:database_type_handler).and_return(database_type_handler)
    allow(service).to receive(:run_ansible_playbook)
  end

  describe '#deploy_primary!' do
    before do
      allow(database_type_handler).to receive(:primary_playbook).and_return('mysql/create_node.yml')
    end

    it 'runs the primary playbook with root password' do
      root_password = node.root_password
      expect(service).to receive(:run_ansible_playbook).with(
        'mysql/create_node.yml',
        { mysql_root_password: root_password }
      )

      service.deploy_primary!
    end
  end

  describe '#deploy_replica!' do
    let(:replica_service) { DeploymentServices::MysqlDeploymentService.new(replica_node) }
    let(:primary_ip) { '192.168.1.100' }
    let(:replication_password) { 'repl_password' }

    before do
      allow(replica_node).to receive(:database_type_handler).and_return(database_type_handler)
      allow(database_type_handler).to receive(:replica_playbook).and_return('mysql/configure_replica.yml')
      allow(parent_node).to receive(:get_ip_address).and_return(primary_ip)
      allow(parent_node).to receive(:get_replication_password).and_return(replication_password)
      allow(replica_service).to receive(:run_ansible_playbook)
    end

    context 'with valid parent node' do
      it 'runs the replica playbook with primary connection details' do
        root_password = replica_node.root_password
        expect(replica_service).to receive(:run_ansible_playbook).with(
          'mysql/configure_replica.yml',
          {
            primary_host: primary_ip,
            replication_password: replication_password,
            mysql_root_password: root_password
          }
        )

        replica_service.deploy_replica!
      end
    end

    context 'without parent node' do
      let(:orphan_replica) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: nil) }
      let(:orphan_service) { DeploymentServices::MysqlDeploymentService.new(orphan_replica) }

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
      allow(database_type_handler).to receive(:primary_replication_playbook).and_return('mysql/configure_primary_replication.yml')
      allow(node).to receive(:get_replication_password).and_return('repl_password')
      allow(node).to receive(:ensure_replication_password!)
      allow(node).to receive(:ensure_root_password!).and_return('root_password')
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
          'mysql/configure_primary_replication.yml',
          {
            replication_password: 'repl_password',
            mysql_root_password: 'root_password'
          }
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
      allow(database_type_handler).to receive(:cleanup_playbook).and_return('mysql/cleanup_replica_config.yml')
      allow(node).to receive(:ensure_root_password!).and_return('root_password')
    end

    it 'runs the cleanup playbook' do
      expect(service).to receive(:run_ansible_playbook).with(
        'mysql/cleanup_replica_config.yml',
        { mysql_root_password: 'root_password' }
      )
      service.cleanup_replication!
    end
  end

  describe '#create_user!' do
    let(:username) { 'testuser' }
    let(:password) { 'testpass' }

    before do
      allow(database_type_handler).to receive(:create_user_playbook).and_return('mysql/create_user.yml')
    end

    it 'runs the create user playbook with default privileges' do
      root_password = node.root_password
      expect(service).to receive(:run_ansible_playbook).with(
        'mysql/create_user.yml',
        {
          username: username,
          password: password,
          privileges: '*.*:ALL',
          host: '%',
          mysql_root_password: root_password
        }
      )

      service.create_user!(username, password)
    end

    it 'runs the create user playbook with custom privileges' do
      root_password = node.root_password
      expect(service).to receive(:run_ansible_playbook).with(
        'mysql/create_user.yml',
        {
          username: username,
          password: password,
          privileges: 'testdb.*:SELECT,INSERT',
          host: '%',
          mysql_root_password: root_password
        }
      )

      service.create_user!(username, password, 'testdb.*:SELECT,INSERT')
    end
  end

  describe '#destroy_user!' do
    let(:username) { 'testuser' }

    before do
      allow(database_type_handler).to receive(:destroy_user_playbook).and_return('mysql/destroy_user.yml')
      allow(node).to receive(:ensure_root_password!).and_return('root_password')
    end

    it 'runs the destroy user playbook' do
      expect(service).to receive(:run_ansible_playbook).with(
        'mysql/destroy_user.yml',
        {
          username: username,
          mysql_root_password: 'root_password'
        }
      )

      service.destroy_user!(username)
    end
  end

  describe '#backup_database' do
    let(:database_name) { 'testdb' }
    let(:backup_file) { 'backup.sql' }

    it 'runs the backup playbook with database name and backup file' do
      root_password = node.root_password
      expect(service).to receive(:run_ansible_playbook).with(
        'mysql/backup_database.yml',
        {
          database_name: database_name,
          backup_file: backup_file,
          mysql_root_password: root_password
        }
      )

      service.backup_database(database_name, backup_file)
    end
  end

  describe '#restore_database' do
    let(:database_name) { 'testdb' }
    let(:backup_file) { 'backup.sql' }

    it 'runs the restore playbook with database name and backup file' do
      root_password = node.root_password
      expect(service).to receive(:run_ansible_playbook).with(
        'mysql/restore_database.yml',
        {
          database_name: database_name,
          backup_file: backup_file,
          mysql_root_password: root_password
        }
      )

      service.restore_database(database_name, backup_file)
    end
  end

  describe '#check_replication_status' do
    context 'for replica node' do
      before do
        allow(node).to receive(:replica?).and_return(true)
      end

      it 'runs the check replica status playbook' do
        root_password = node.root_password
        expect(service).to receive(:run_ansible_playbook).with(
          'mysql/check_replica_status.yml',
          { mysql_root_password: root_password }
        )

        service.check_replication_status
      end
    end

    context 'for primary node' do
      before do
        allow(node).to receive(:replica?).and_return(false)
      end

      it 'runs the check primary status playbook' do
        root_password = node.root_password
        expect(service).to receive(:run_ansible_playbook).with(
          'mysql/check_primary_status.yml',
          { mysql_root_password: root_password }
        )

        service.check_replication_status
      end
    end
  end

  describe '#get_root_password (private method)' do
    it 'retrieves the stored root password from node' do
      expect(node).to receive(:ensure_root_password!)
      service.send(:get_root_password)
    end
  end
end

