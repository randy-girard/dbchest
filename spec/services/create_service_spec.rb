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
        allow(replica_node).to receive(:reload).and_return(replica_node)
        allow(replica_node).to receive(:get_ip_address).and_return('192.168.1.100')
        allow(replica_node).to receive(:parent_node).and_return(parent_node)
        allow(Node).to receive(:find_by_id).with(replica_node.id).and_return(replica_node)
        allow(ConfigurePrimaryForReplicaJob).to receive(:perform_later)
      end

      it 'triggers ConfigurePrimaryForReplicaJob after Terraform' do
        expect(ConfigurePrimaryForReplicaJob).to receive(:perform_later).with(
          primary_node_id: parent_node.id,
          replica_node_id: replica_node.id,
          replica_ip: '192.168.1.100'
        )

        service.perform(replica_node.id, true)
      end

      it 'calls TerraformCreateService for replica' do
        terraform_service = instance_double(TerraformCreateService)
        expect(TerraformCreateService).to receive(:new).and_return(terraform_service)
        expect(terraform_service).to receive(:perform).with(replica_node.id)

        service.perform(replica_node.id, true)
      end

      it 'reloads node to get IP address from Terraform' do
        expect(replica_node).to receive(:reload)
        service.perform(replica_node.id, true)
      end

      it 'does not trigger job if replica has no IP' do
        allow(replica_node).to receive(:get_ip_address).and_return(nil)
        expect(ConfigurePrimaryForReplicaJob).not_to receive(:perform_later)
        service.perform(replica_node.id, true)
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
