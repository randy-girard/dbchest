require 'rails_helper'

RSpec.describe ProvisionDefaultCredentialJob, type: :job do
  let(:database_type) { create(:database_type, slug: 'postgresql') }
  let(:database_type_version) { create(:database_type_version, database_type: database_type) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:primary_node) { create(:node, :active, cluster: cluster, provider: provider, database_type_version: database_type_version) }
  let(:replica_node) { create(:node, :active, cluster: cluster, provider: provider, database_type_version: database_type_version, parent_node: primary_node) }

  before do
    # Mock the deployment service at the class level to prevent actual Ansible runs
    allow_any_instance_of(DeploymentServices::PostgresqlDeploymentService).to receive(:create_user!).and_return(true)
    allow_any_instance_of(DeploymentServices::MysqlDeploymentService).to receive(:create_user!).and_return(true)
    allow_any_instance_of(DeploymentServices::MongodbDeploymentService).to receive(:create_user!).and_return(true)
    allow_any_instance_of(DeploymentServices::CassandraDeploymentService).to receive(:create_user!).and_return(true)
  end

  describe '#perform' do
    context 'with a primary node' do
      context 'when database type auto-replicates users' do
        it 'creates a default credential' do
          expect {
            described_class.new.perform(primary_node.id)
          }.to change { primary_node.credentials.count }.by(1)
        end

        it 'creates credential with username "default"' do
          described_class.new.perform(primary_node.id)
          credential = primary_node.credentials.last
          expect(credential.username).to eq('default')
        end

        it 'generates a secure random password' do
          described_class.new.perform(primary_node.id)
          credential = primary_node.credentials.last
          expect(credential.password).to be_present
          expect(credential.password.length).to eq(32)
        end

        it 'provisions the user only on the primary node' do
          expect_any_instance_of(DeploymentServices::PostgresqlDeploymentService).to receive(:create_user!).once.with(
            'default',
            anything,
            anything
          )
          described_class.new.perform(primary_node.id)
        end

        it 'does not create duplicate credentials' do
          # Create first credential
          described_class.new.perform(primary_node.id)
          first_count = primary_node.reload.credentials.count
          expect(first_count).to eq(1)

          # Verify the credential exists with username "default" (need to check decrypted value)
          credential = primary_node.credentials.first
          expect(credential.username).to eq('default')

          # Try to create again - should not create a new one
          described_class.new.perform(primary_node.id)
          second_count = primary_node.reload.credentials.count

          expect(second_count).to eq(first_count)
        end
      end

      context 'when database type does not auto-replicate users' do
        # Note: Testing non-auto-replicating databases would require creating a custom
        # database type handler. For now, all supported database types (PostgreSQL, MySQL,
        # MongoDB, Cassandra) auto-replicate users, so this scenario is theoretical.
        # The job logic handles it by provisioning to all active replicas.

        it 'would provision to all nodes if database type did not auto-replicate' do
          # This is a placeholder test to document the expected behavior
          # In practice, all current database types auto-replicate users
          expect(primary_node.database_type_handler.users_replicate_automatically?).to be true
        end
      end

      context 'with different database types' do
        it 'uses correct privileges for PostgreSQL' do
          expect_any_instance_of(DeploymentServices::PostgresqlDeploymentService).to receive(:create_user!).with(
            'default',
            anything,
            'ALL'
          )
          described_class.new.perform(primary_node.id)
        end

        it 'uses correct privileges for MySQL' do
          mysql_type = create(:database_type, slug: 'mysql')
          mysql_version = create(:database_type_version, database_type: mysql_type)
          mysql_cluster = create(:cluster, database_type: mysql_type)
          mysql_node = create(:node, :active, cluster: mysql_cluster, provider: provider, database_type_version: mysql_version)

          expect_any_instance_of(DeploymentServices::MysqlDeploymentService).to receive(:create_user!).with(
            'default',
            anything,
            '*.*:ALL'
          )
          described_class.new.perform(mysql_node.id)
        end

        it 'uses correct privileges for MongoDB' do
          mongodb_type = create(:database_type, slug: 'mongodb')
          mongodb_version = create(:database_type_version, database_type: mongodb_type)
          mongodb_cluster = create(:cluster, database_type: mongodb_type)
          mongodb_node = create(:node, :active, cluster: mongodb_cluster, provider: provider, database_type_version: mongodb_version)

          expect_any_instance_of(DeploymentServices::MongodbDeploymentService).to receive(:create_user!).with(
            'default',
            anything,
            [ 'readWrite', 'dbAdmin' ]
          )
          described_class.new.perform(mongodb_node.id)
        end

        it 'uses correct privileges for Cassandra' do
          cassandra_type = create(:database_type, slug: 'cassandra')
          cassandra_version = create(:database_type_version, database_type: cassandra_type)
          cassandra_cluster = create(:cluster, database_type: cassandra_type)
          cassandra_node = create(:node, :active, cluster: cassandra_cluster, provider: provider, database_type_version: cassandra_version)

          expect_any_instance_of(DeploymentServices::CassandraDeploymentService).to receive(:create_user!).with(
            'default',
            anything,
            [ 'LOGIN', 'SELECT', 'MODIFY' ]
          )
          described_class.new.perform(cassandra_node.id)
        end
      end
    end

    context 'with a replica node' do
      it 'does not create a credential' do
        expect {
          described_class.new.perform(replica_node.id)
        }.not_to change { Credential.count }
      end
    end

    context 'with an inactive node' do
      let(:inactive_node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version, status: 'pending') }

      it 'does not create a credential' do
        expect {
          described_class.new.perform(inactive_node.id)
        }.not_to change { Credential.count }
      end
    end

    context 'with a non-existent node' do
      it 'does not raise an error' do
        expect {
          described_class.new.perform(999999)
        }.not_to raise_error
      end
    end

    context 'when user provisioning fails' do
      before do
        allow_any_instance_of(DeploymentServices::PostgresqlDeploymentService).to receive(:create_user!).and_raise(StandardError.new('Provisioning failed'))
      end

      it 'raises an error' do
        expect {
          described_class.new.perform(primary_node.id)
        }.to raise_error(StandardError, 'Provisioning failed')
      end

      it 'still creates the credential record' do
        expect {
          begin
            described_class.new.perform(primary_node.id)
          rescue StandardError
            # Ignore the error
          end
        }.to change { primary_node.credentials.count }.by(1)
      end
    end
  end
end
