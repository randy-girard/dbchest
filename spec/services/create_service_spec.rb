require 'rails_helper'

RSpec.describe CreateService, type: :service do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
  let(:parent_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, status: 'active') }
  let(:replica_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: parent_node) }
  let(:service) { CreateService.new }

  before do
    # Mock external services to avoid actual infrastructure calls
    allow_any_instance_of(TerraformCreateService).to receive(:perform)
    allow_any_instance_of(ReplicaConfigurationService).to receive(:configure_primary_for_replica)
    allow_any_instance_of(Node).to receive(:update_status!)
  end

  describe '#perform' do
    context 'with valid node' do
      it 'updates node status to provisioning' do
        allow(Node).to receive(:find_by_id).with(node.id).and_return(node)
        expect(node).to receive(:update_status!).with('provisioning', 'Starting infrastructure provisioning...')
        service.perform(node.id)
      end

      it 'calls TerraformCreateService' do
        terraform_service = instance_double(TerraformCreateService)
        expect(TerraformCreateService).to receive(:new).and_return(terraform_service)
        expect(terraform_service).to receive(:perform).with(node.id)
        
        service.perform(node.id)
      end

      it 'does not configure primary for non-replica nodes' do
        expect_any_instance_of(ReplicaConfigurationService).not_to receive(:configure_primary_for_replica)
        service.perform(node.id)
      end
    end

    context 'with replica node' do
      before do
        allow(replica_node).to receive(:replica?).and_return(true)
        allow(Node).to receive(:find_by_id).with(replica_node.id).and_return(replica_node)
      end

      it 'configures primary node for replica when is_replica is true' do
        replica_config_service = instance_double(ReplicaConfigurationService)
        expect(ReplicaConfigurationService).to receive(:new).and_return(replica_config_service)
        expect(replica_config_service).to receive(:configure_primary_for_replica).with(parent_node.id, replica_node.id)
        
        service.perform(replica_node.id, true)
      end

      it 'updates status for replica configuration' do
        allow(Node).to receive(:find_by_id).with(replica_node.id).and_return(replica_node)
        expect(replica_node).to receive(:update_status!).with('provisioning', 'Starting infrastructure provisioning...')
        expect(replica_node).to receive(:update_status!).with('provisioning', 'Configuring primary node for specific replica IP...')
        service.perform(replica_node.id, true)
      end

      it 'logs replica configuration' do
        expect(Rails.logger).to receive(:info).with(/Configuring primary node #{parent_node.id} for new replica #{replica_node.id}/)
        service.perform(replica_node.id, true)
      end

      it 'does not configure primary when is_replica is false' do
        expect_any_instance_of(ReplicaConfigurationService).not_to receive(:configure_primary_for_replica)
        service.perform(replica_node.id, false)
      end
    end

    context 'with non-existent node' do
      it 'does not raise error when node is not found' do
        expect { service.perform(999999) }.not_to raise_error
      end

      it 'does not call TerraformCreateService when node is not found' do
        expect_any_instance_of(TerraformCreateService).not_to receive(:perform)
        service.perform(999999)
      end
    end

    context 'when an error occurs' do
      let(:error_message) { 'Infrastructure creation failed' }

      before do
        allow(Node).to receive(:find_by_id).with(node.id).and_return(node)
        allow_any_instance_of(TerraformCreateService).to receive(:perform).and_raise(StandardError.new(error_message))
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with("Error in CreateService for node #{node.id}: #{error_message}")
        expect { service.perform(node.id) }.to raise_error(StandardError)
      end

      it 'updates node status to error' do
        allow(Node).to receive(:find_by_id).with(node.id).and_return(node)
        expect(node).to receive(:update_status!).with('provisioning', 'Starting infrastructure provisioning...')
        expect(node).to receive(:update_status!).with('error', "Failed: #{error_message}")
        expect { service.perform(node.id) }.to raise_error(StandardError)
      end

      it 're-raises the error' do
        expect { service.perform(node.id) }.to raise_error(StandardError, error_message)
      end
    end
  end

  describe 'Sidekiq integration' do
    it 'includes Sidekiq::Job' do
      expect(CreateService.ancestors).to include(Sidekiq::Job)
    end
  end
end
