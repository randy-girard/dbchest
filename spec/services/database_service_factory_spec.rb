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

      it 'raises an ArgumentError' do
        expect {
          DatabaseServiceFactory.deployment_service_for(node)
        }.to raise_error(ArgumentError, "Unknown database type: unknown")
      end
    end
  end

  describe '.monitoring_service_for' do
    context 'with postgresql node' do
      let(:node) { create(:node, cluster: postgresql_cluster, provider: provider, database_type_version: postgresql_version) }

      it 'returns a PostgresqlMonitoringService instance' do
        # Mock the monitoring service class since it might not exist yet
        monitoring_service_class = double('PostgresqlMonitoringService')
        monitoring_service_instance = double('monitoring_service_instance')
        
        stub_const('DeploymentServices::PostgresqlMonitoringService', monitoring_service_class)
        expect(monitoring_service_class).to receive(:new).with(node).and_return(monitoring_service_instance)
        
        service = DatabaseServiceFactory.monitoring_service_for(node)
        expect(service).to eq(monitoring_service_instance)
      end
    end

    context 'with mysql node' do
      let(:node) { create(:node, cluster: mysql_cluster, provider: provider, database_type_version: mysql_version) }

      it 'returns a MysqlMonitoringService instance' do
        # Mock the monitoring service class since it might not exist yet
        monitoring_service_class = double('MysqlMonitoringService')
        monitoring_service_instance = double('monitoring_service_instance')
        
        stub_const('DeploymentServices::MysqlMonitoringService', monitoring_service_class)
        expect(monitoring_service_class).to receive(:new).with(node).and_return(monitoring_service_instance)
        
        service = DatabaseServiceFactory.monitoring_service_for(node)
        expect(service).to eq(monitoring_service_instance)
      end
    end

    context 'with unknown database type' do
      let(:unknown_database_type) { create(:database_type, slug: 'unknown') }
      let(:unknown_version) { create(:database_type_version, database_type: unknown_database_type) }
      let(:unknown_cluster) { create(:cluster, database_type: unknown_database_type) }
      let(:node) { create(:node, cluster: unknown_cluster, provider: provider, database_type_version: unknown_version) }

      it 'raises an ArgumentError' do
        expect {
          DatabaseServiceFactory.monitoring_service_for(node)
        }.to raise_error(ArgumentError, "Unknown database type: unknown")
      end
    end
  end
end
