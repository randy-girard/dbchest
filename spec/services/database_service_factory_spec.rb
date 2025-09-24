require 'rails_helper'

RSpec.describe DatabaseServiceFactory, type: :service do
  let(:postgresql_database_type) { create(:database_type, slug: 'postgresql') }
  let(:mysql_database_type) { create(:database_type, slug: 'mysql') }
  let(:postgresql_version) { create(:database_type_version, database_type: postgresql_database_type) }
  let(:mysql_version) { create(:database_type_version, database_type: mysql_database_type) }
  let(:postgresql_cluster) { create(:cluster, database_type: postgresql_database_type) }
  let(:mysql_cluster) { create(:cluster, database_type: mysql_database_type) }
  let(:provider) { create(:provider) }

  describe '.cloud_init_service_for' do
    let(:node) { create(:node, cluster: postgresql_cluster, provider: provider, database_type_version: postgresql_version) }

    it 'returns a CloudInitService instance' do
      service = DatabaseServiceFactory.cloud_init_service_for(node)
      expect(service).to be_a(CloudInitService)
    end
  end

  describe '.ansible_service_for' do
    let(:node) { create(:node, cluster: postgresql_cluster, provider: provider, database_type_version: postgresql_version) }

    it 'returns an AnsibleRunService instance' do
      service = DatabaseServiceFactory.ansible_service_for(node)
      expect(service).to be_a(AnsibleRunService)
    end
  end

  describe '.deployment_service_for' do
    context 'with postgresql node' do
      let(:node) { create(:node, cluster: postgresql_cluster, provider: provider, database_type_version: postgresql_version) }

      it 'returns a PostgresqlDeploymentService instance' do
        service = DatabaseServiceFactory.deployment_service_for(node)
        expect(service).to be_a(DeploymentServices::PostgresqlDeploymentService)
      end

      it 'initializes the service with the node' do
        expect(DeploymentServices::PostgresqlDeploymentService).to receive(:new).with(node)
        DatabaseServiceFactory.deployment_service_for(node)
      end
    end

    context 'with mysql node' do
      let(:node) { create(:node, cluster: mysql_cluster, provider: provider, database_type_version: mysql_version) }

      it 'returns a MysqlDeploymentService instance' do
        service = DatabaseServiceFactory.deployment_service_for(node)
        expect(service).to be_a(DeploymentServices::MysqlDeploymentService)
      end

      it 'initializes the service with the node' do
        expect(DeploymentServices::MysqlDeploymentService).to receive(:new).with(node)
        DatabaseServiceFactory.deployment_service_for(node)
      end
    end

    context 'with unknown database type' do
      let(:unknown_database_type) { create(:database_type, slug: 'unknown') }
      let(:unknown_version) { create(:database_type_version, database_type: unknown_database_type) }
      let(:unknown_cluster) { create(:cluster, database_type: unknown_database_type) }
      let(:node) { create(:node, cluster: unknown_cluster, provider: provider, database_type_version: unknown_version) }

      it 'raises an ArgumentError with available types' do
        expect {
          DatabaseServiceFactory.deployment_service_for(node)
        }.to raise_error(ArgumentError, /Unknown database type: unknown. Available types:/)
      end
    end
  end

  describe '.monitoring_service_for' do
    context 'with postgresql node' do
      let(:node) { create(:node, cluster: postgresql_cluster, provider: provider, database_type_version: postgresql_version) }

      it 'raises error since monitoring services are not yet implemented' do
        expect {
          DatabaseServiceFactory.monitoring_service_for(node)
        }.to raise_error(ArgumentError, /Unknown database type: postgresql. Available types:/)
      end
    end

    context 'with mysql node' do
      let(:node) { create(:node, cluster: mysql_cluster, provider: provider, database_type_version: mysql_version) }

      it 'raises error since monitoring services are not yet implemented' do
        expect {
          DatabaseServiceFactory.monitoring_service_for(node)
        }.to raise_error(ArgumentError, /Unknown database type: mysql. Available types:/)
      end
    end

    context 'with unknown database type' do
      let(:unknown_database_type) { create(:database_type, slug: 'unknown') }
      let(:unknown_version) { create(:database_type_version, database_type: unknown_database_type) }
      let(:unknown_cluster) { create(:cluster, database_type: unknown_database_type) }
      let(:node) { create(:node, cluster: unknown_cluster, provider: provider, database_type_version: unknown_version) }

      it 'raises an ArgumentError with available types' do
        expect {
          DatabaseServiceFactory.monitoring_service_for(node)
        }.to raise_error(ArgumentError, /Unknown database type: unknown. Available types:/)
      end
    end
  end

  describe 'registry methods' do
    describe '.register_deployment_service' do
      it 'registers a deployment service' do
        test_service = Class.new
        DatabaseServiceFactory.register_deployment_service('test_db', test_service)

        expect(DatabaseServiceFactory.registered_deployment_types).to include('test_db')
      end
    end

    describe '.register_monitoring_service' do
      it 'registers a monitoring service' do
        test_service = Class.new
        DatabaseServiceFactory.register_monitoring_service('test_db', test_service)

        expect(DatabaseServiceFactory.registered_monitoring_types).to include('test_db')
      end
    end

    describe '.registered_deployment_types' do
      it 'returns list of registered deployment service types' do
        types = DatabaseServiceFactory.registered_deployment_types
        expect(types).to include('postgresql', 'mysql')
      end
    end

    describe '.registered_monitoring_types' do
      it 'returns list of registered monitoring service types' do
        types = DatabaseServiceFactory.registered_monitoring_types
        expect(types).to be_an(Array)
      end
    end
  end
end
