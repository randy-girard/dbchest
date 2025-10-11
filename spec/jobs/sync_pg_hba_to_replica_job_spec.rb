require 'rails_helper'

RSpec.describe SyncPgHbaToReplicaJob, type: :job do
  let(:postgresql_database_type) { create(:database_type, slug: 'postgresql', name: 'PostgreSQL') }
  let(:cluster) { create(:cluster, database_type: postgresql_database_type) }
  let(:postgresql_version) { create(:database_type_version, database_type: postgresql_database_type, version: '15') }
  let(:provider) { create(:provider) }
  let(:primary_node) { create(:node, cluster: cluster, provider: provider, database_type_version: postgresql_version, parent_node: nil, status: 'active') }
  let(:replica_node) { create(:node, cluster: cluster, provider: provider, database_type_version: postgresql_version, parent_node: primary_node, status: 'active') }

  before do
    # Mock the database type handler
    allow_any_instance_of(Node).to receive(:database_type_handler).and_return(
      double(users_replicate_automatically?: true)
    )
  end

  describe '#perform' do
    context 'when adding pg_hba entry' do
      it 'runs Ansible playbook to add entry' do
        expect_any_instance_of(AnsibleRunService).to receive(:perform).with(
          replica_node.id,
          "sync_replica_pg_hba.yml",
          vars: {
            username: 'testuser',
            action: 'add',
            postgresql_version: '15'
          }
        ).and_return({ success: true })

        SyncPgHbaToReplicaJob.perform_now(replica_node.id, 'testuser', 'add')
      end
    end

    context 'when removing pg_hba entry' do
      it 'runs Ansible playbook to remove entry' do
        expect_any_instance_of(AnsibleRunService).to receive(:perform).with(
          replica_node.id,
          "sync_replica_pg_hba.yml",
          vars: {
            username: 'testuser',
            action: 'remove',
            postgresql_version: '15'
          }
        ).and_return({ success: true })

        SyncPgHbaToReplicaJob.perform_now(replica_node.id, 'testuser', 'remove')
      end
    end

    context 'when node is not a replica' do
      it 'does not run Ansible playbook' do
        expect_any_instance_of(AnsibleRunService).not_to receive(:perform)

        SyncPgHbaToReplicaJob.perform_now(primary_node.id, 'testuser', 'add')
      end
    end

    context 'when database type does not support automatic user replication' do
      before do
        allow_any_instance_of(Node).to receive(:database_type_handler).and_return(
          double(users_replicate_automatically?: false)
        )
      end

      it 'does not run Ansible playbook' do
        expect_any_instance_of(AnsibleRunService).not_to receive(:perform)

        SyncPgHbaToReplicaJob.perform_now(replica_node.id, 'testuser', 'add')
      end
    end

    context 'when node does not exist' do
      it 'does not raise an error' do
        expect {
          SyncPgHbaToReplicaJob.perform_now(99999, 'testuser', 'add')
        }.not_to raise_error
      end
    end

    context 'error handling' do
      it 'logs errors but does not raise' do
        allow_any_instance_of(AnsibleRunService).to receive(:perform).and_raise(StandardError.new("Ansible failed"))
        allow(Rails.logger).to receive(:error)

        expect {
          SyncPgHbaToReplicaJob.perform_now(replica_node.id, 'testuser', 'add')
        }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(/Error syncing pg_hba/).at_least(:once)
      end
    end
  end
end
