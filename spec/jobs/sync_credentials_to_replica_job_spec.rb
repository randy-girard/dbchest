require 'rails_helper'

RSpec.describe SyncCredentialsToReplicaJob, type: :job do
  let(:mysql_database_type) { create(:database_type, slug: 'mysql', name: 'MySQL') }
  let(:mysql_cluster) { create(:cluster, database_type: mysql_database_type) }
  let(:mysql_version) { create(:database_type_version, database_type: mysql_database_type, version: '8.0') }
  let(:provider) { create(:provider) }
  let(:primary_node) { create(:node, cluster: mysql_cluster, provider: provider, database_type_version: mysql_version, parent_node: nil) }
  let(:replica_node) { create(:node, cluster: mysql_cluster, provider: provider, database_type_version: mysql_version, parent_node: primary_node, status: 'active') }

  before do
    # Mock the database type handler
    allow_any_instance_of(Node).to receive(:database_type_handler).and_return(
      double(users_replicate_automatically?: true)
    )
  end

  describe '#perform' do
    context 'when replica has no credentials' do
      it 'creates replicated credentials for all primary credentials' do
        # Create credentials on primary (without triggering automatic replication)
        allow_any_instance_of(Credential).to receive(:replicate_to_replicas)

        credential1 = primary_node.credentials.create!(username: 'user1', password: 'pass1')
        credential2 = primary_node.credentials.create!(username: 'user2', password: 'pass2')

        expect {
          SyncCredentialsToReplicaJob.perform_now(replica_node.id)
        }.to change { replica_node.credentials.count }.by(2)
      end

      it 'sets correct attributes on replicated credentials' do
        allow_any_instance_of(Credential).to receive(:replicate_to_replicas)

        primary_credential = primary_node.credentials.create!(username: 'testuser', password: 'testpass')

        SyncCredentialsToReplicaJob.perform_now(replica_node.id)

        replica_credential = replica_node.credentials.find_by(source_credential_id: primary_credential.id)
        expect(replica_credential).to be_present
        expect(replica_credential.username).to eq('testuser')
        expect(replica_credential.password).to eq('testpass')
        expect(replica_credential.is_replicated?).to be true
        expect(replica_credential.source_credential_id).to eq(primary_credential.id)
      end
    end

    context 'when replica already has some credentials' do
      it 'only creates missing credentials' do
        allow_any_instance_of(Credential).to receive(:replicate_to_replicas)

        credential1 = primary_node.credentials.create!(username: 'user1', password: 'pass1')
        credential2 = primary_node.credentials.create!(username: 'user2', password: 'pass2')

        # Manually create one replicated credential
        replica_node.credentials.create!(
          username: 'user1',
          password: 'pass1',
          source_credential_id: credential1.id,
          is_replicated: true
        )

        expect {
          SyncCredentialsToReplicaJob.perform_now(replica_node.id)
        }.to change { replica_node.credentials.count }.by(1)
      end

      it 'does not duplicate existing credentials' do
        allow_any_instance_of(Credential).to receive(:replicate_to_replicas)

        credential1 = primary_node.credentials.create!(username: 'user1', password: 'pass1')

        # Manually create replicated credential
        replica_node.credentials.create!(
          username: 'user1',
          password: 'pass1',
          source_credential_id: credential1.id,
          is_replicated: true
        )

        expect {
          SyncCredentialsToReplicaJob.perform_now(replica_node.id)
        }.not_to change { replica_node.credentials.count }
      end
    end

    context 'when node is not a replica' do
      it 'does not create any credentials' do
        allow_any_instance_of(Credential).to receive(:replicate_to_replicas)

        primary_node.credentials.create!(username: 'user1', password: 'pass1')

        expect {
          SyncCredentialsToReplicaJob.perform_now(primary_node.id)
        }.not_to change { primary_node.credentials.count }
      end
    end

    context 'when database type does not support automatic user replication' do
      before do
        allow_any_instance_of(Node).to receive(:database_type_handler).and_return(
          double(users_replicate_automatically?: false)
        )
      end

      it 'does not create any credentials' do
        allow_any_instance_of(Credential).to receive(:replicate_to_replicas)

        primary_node.credentials.create!(username: 'user1', password: 'pass1')

        expect {
          SyncCredentialsToReplicaJob.perform_now(replica_node.id)
        }.not_to change { replica_node.credentials.count }
      end
    end

    context 'when node does not exist' do
      it 'does not raise an error' do
        expect {
          SyncCredentialsToReplicaJob.perform_now(99999)
        }.not_to raise_error
      end
    end

    context 'error handling' do
      it 'handles errors gracefully when credential creation fails' do
        allow_any_instance_of(Credential).to receive(:replicate_to_replicas)

        credential1 = primary_node.credentials.create!(username: 'user1', password: 'pass1')
        credential2 = primary_node.credentials.create!(username: 'user2', password: 'pass2')

        # Make the first credential fail
        call_count = 0
        allow(replica_node.credentials).to receive(:create!) do
          call_count += 1
          if call_count == 1
            raise ActiveRecord::RecordInvalid.new(Credential.new)
          else
            # Allow the second one to succeed
            Credential.create!(
              node: replica_node,
              username: credential2.username,
              password: credential2.password,
              source_credential_id: credential2.id,
              is_replicated: true
            )
          end
        end

        # Should not raise an error
        expect {
          SyncCredentialsToReplicaJob.perform_now(replica_node.id)
        }.not_to raise_error
      end
    end
  end
end
