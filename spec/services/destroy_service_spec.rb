require 'rails_helper'

RSpec.describe DestroyService, type: :service do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
  let(:parent_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, status: 'active') }
  let(:replica_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: parent_node) }
  let(:service) { DestroyService.new }

  before do
    # Mock external services to avoid actual infrastructure calls
    allow_any_instance_of(TerraformDestroyService).to receive(:perform)
    allow_any_instance_of(AnsibleRunService).to receive(:perform)
    allow_any_instance_of(Node).to receive(:update_status!)
    allow_any_instance_of(Node).to receive(:destroy!)
  end

  describe '#perform' do
    context 'with valid node' do
      before do
        allow(Node).to receive(:find_by_id).with(node.id).and_return(node)
      end

      it 'updates node status to destroying' do
        allow(Node).to receive(:find_by_id).with(node.id).and_return(node)
        expect(node).to receive(:update_status!).with('destroying', 'Starting node destruction...')
        expect(node).to receive(:update_status!).with('destroying', 'Destroying infrastructure...')
        expect(node).to receive(:update_status!).with('destroyed', 'Node has been destroyed')
        service.perform(node.id)
      end

      it 'calls TerraformDestroyService' do
        terraform_service = instance_double(TerraformDestroyService)
        expect(TerraformDestroyService).to receive(:new).and_return(terraform_service)
        expect(terraform_service).to receive(:perform).with(node.id)

        service.perform(node.id)
      end

      it 'updates status to destroying infrastructure' do
        allow(Node).to receive(:find_by_id).with(node.id).and_return(node)
        allow(node).to receive(:update_status!)
        expect(node).to receive(:update_status!).with('destroying', 'Destroying infrastructure...')
        service.perform(node.id)
      end

      it 'updates status to destroyed' do
        allow(Node).to receive(:find_by_id).with(node.id).and_return(node)
        allow(node).to receive(:update_status!)
        expect(node).to receive(:update_status!).with('destroyed', 'Node has been destroyed')
        service.perform(node.id)
      end

      it 'destroys the node' do
        expect(node).to receive(:destroy!)
        service.perform(node.id)
      end
    end

    context 'with replica node' do
      let(:replica_ip) { '192.168.1.100' }

      before do
        allow(Node).to receive(:find_by_id).with(replica_node.id).and_return(replica_node)
        allow(replica_node).to receive(:replica?).and_return(true)
        allow(replica_node).to receive(:parent_node).and_return(parent_node)
        allow(replica_node).to receive(:get_ip_address).and_return(replica_ip)
      end

      it 'cleans up replication configuration' do
        ansible_service = instance_double(AnsibleRunService)
        expect(AnsibleRunService).to receive(:new).and_return(ansible_service)
        expect(ansible_service).to receive(:perform).with(
          parent_node.id,
          "cleanup_replica_config.yml",
          vars: {
            replica_ip: replica_ip,
            postgresql_version: parent_node.database_type_version&.version || '15'
          }
        )

        service.perform(replica_node.id)
      end

      it 'updates status for replication cleanup' do
        allow(Node).to receive(:find_by_id).with(replica_node.id).and_return(replica_node)
        allow(replica_node).to receive(:update_status!)
        expect(replica_node).to receive(:update_status!).with('destroying', 'Cleaning up replication configuration...')
        service.perform(replica_node.id)
      end

      it 'logs replication cleanup' do
        expect(Rails.logger).to receive(:info).with("Cleaning up pg_hba.conf entries for replica IP: #{replica_ip}")
        service.perform(replica_node.id)
      end

      context 'when replica has no IP address' do
        before do
          allow(replica_node).to receive(:get_ip_address).and_return(nil)
        end

        it 'skips replication cleanup' do
          expect_any_instance_of(AnsibleRunService).not_to receive(:perform)
          service.perform(replica_node.id)
        end

        it 'logs warning about missing IP' do
          expect(Rails.logger).to receive(:warn).with("Skipping pg_hba.conf cleanup for replica node #{replica_node.id}: no IP address found")
          service.perform(replica_node.id)
        end
      end

      context 'when replica has no parent node' do
        before do
          allow(replica_node).to receive(:parent_node).and_return(nil)
        end

        it 'skips replication cleanup' do
          expect_any_instance_of(AnsibleRunService).not_to receive(:perform)
          service.perform(replica_node.id)
        end
      end
    end

    context 'with non-existent node' do
      it 'returns early when node is not found' do
        expect_any_instance_of(TerraformDestroyService).not_to receive(:perform)
        service.perform(999999)
      end
    end

    context 'when an error occurs' do
      let(:error_message) { 'Infrastructure destruction failed' }

      before do
        allow(Node).to receive(:find_by_id).with(node.id).and_return(node)
        allow_any_instance_of(TerraformDestroyService).to receive(:perform).and_raise(StandardError.new(error_message))
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with("Error in DestroyService for node #{node.id}: #{error_message}")
        expect { service.perform(node.id) }.to raise_error(StandardError)
      end

      it 'updates node status to error' do
        allow(Node).to receive(:find_by_id).with(node.id).and_return(node)
        allow(node).to receive(:update_status!)
        expect(node).to receive(:update_status!).with('error', "Destruction failed: #{error_message}")
        expect { service.perform(node.id) }.to raise_error(StandardError)
      end

      it 're-raises the error' do
        expect { service.perform(node.id) }.to raise_error(StandardError, error_message)
      end
    end
  end

  describe 'Sidekiq integration' do
    it 'includes Sidekiq::Job' do
      expect(DestroyService.ancestors).to include(Sidekiq::Job)
    end
  end
end
