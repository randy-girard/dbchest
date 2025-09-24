require 'rails_helper'

RSpec.describe DatabaseTypes::MongodbDatabaseType, type: :service do
  let(:database_type) { create(:database_type, slug: 'mongodb') }
  let(:database_type_version) { create(:database_type_version, database_type: database_type, version: '6.0') }
  let(:handler) { described_class.new(database_type_version) }

  describe '#supports_logical_replication?' do
    context 'with MongoDB 3.0+' do
      it 'returns true' do
        expect(handler.supports_logical_replication?).to be true
      end
    end

    context 'with MongoDB 2.x' do
      let(:database_type_version) { create(:database_type_version, database_type: database_type, version: '2.6') }

      it 'returns false' do
        expect(handler.supports_logical_replication?).to be false
      end
    end
  end

  describe '#supports_streaming_replication?' do
    context 'with MongoDB 3.0+' do
      it 'returns true' do
        expect(handler.supports_streaming_replication?).to be true
      end
    end

    context 'with MongoDB 2.x' do
      let(:database_type_version) { create(:database_type_version, database_type: database_type, version: '2.6') }

      it 'returns false' do
        expect(handler.supports_streaming_replication?).to be false
      end
    end
  end

  describe '#generate_cloud_init_script' do
    let(:cluster) { create(:cluster, database_type: database_type) }
    let(:provider) { create(:provider) }
    let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }

    it 'calls the MongoDB cloud init generator' do
      generator_double = double('generator')
      expect(CloudInitGenerators::MongodbCloudInitGenerator).to receive(:new)
        .with(handler, node)
        .and_return(generator_double)
      expect(generator_double).to receive(:generate).with(is_replica: false)

      handler.generate_cloud_init_script(node)
    end

    it 'passes replica flag correctly' do
      generator_double = double('generator')
      expect(CloudInitGenerators::MongodbCloudInitGenerator).to receive(:new)
        .with(handler, node)
        .and_return(generator_double)
      expect(generator_double).to receive(:generate).with(is_replica: true)

      handler.generate_cloud_init_script(node, is_replica: true)
    end
  end

  describe '#primary_configuration_commands' do
    it 'returns MongoDB primary configuration commands' do
      commands = handler.primary_configuration_commands

      expect(commands).to include(
        match(/replication:/),
        match(/replSetName: "dbchest_rs"/),
        match(/bindIp: 0.0.0.0/)
      )
    end
  end

  describe '#replica_configuration_commands' do
    it 'returns MongoDB replica configuration commands' do
      commands = handler.replica_configuration_commands

      expect(commands).to include(
        match(/replication:/),
        match(/replSetName: "dbchest_rs"/),
        match(/bindIp: 0.0.0.0/)
      )
    end
  end

  describe '#readiness_check_command' do
    it 'returns MongoDB readiness check command' do
      expect(handler.readiness_check_command).to eq('mongosh --eval \'db.runCommand("ping")\' --quiet')
    end
  end

  describe '#create_sample_data_commands' do
    it 'returns MongoDB sample data creation commands' do
      commands = handler.create_sample_data_commands

      expect(commands).to include(
        match(/use dbchest_sample/),
        match(/sample_data.insertMany/)
      )
    end
  end

  describe '#recovery_check_command' do
    it 'returns MongoDB recovery check command' do
      expect(handler.recovery_check_command).to include('rs.isMaster().ismaster')
    end
  end

  describe '#replication_lag_check_commands' do
    it 'returns MongoDB replication lag check commands' do
      commands = handler.replication_lag_check_commands

      expect(commands).to include(
        match(/rs.printSlaveReplicationInfo/)
      )
    end
  end

  describe 'MongoDB-specific methods' do
    describe '#replica_set_name' do
      it 'returns the replica set name' do
        expect(handler.replica_set_name).to eq('dbchest_rs')
      end
    end

    describe '#initiate_replica_set_command' do
      it 'returns replica set initiation command' do
        expect(handler.initiate_replica_set_command).to eq('mongosh --eval \'rs.initiate()\'')
      end
    end

    describe '#add_replica_member_command' do
      it 'returns command to add replica member' do
        command = handler.add_replica_member_command('192.168.1.100')
        expect(command).to include('rs.add("192.168.1.100:')
      end
    end
  end

  describe 'registration' do
    it 'registers itself with the base class' do
      expect(DatabaseTypes::BaseDatabaseType.registered_types).to include('mongodb')
    end
  end
end
