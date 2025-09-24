require 'rails_helper'

RSpec.describe DatabaseTypes::PostgresqlDatabaseType, type: :service do
  let(:database_type) { create(:database_type, slug: 'postgresql') }
  let(:database_type_version) { create(:database_type_version, database_type: database_type, version: '15.0') }
  let(:postgresql_handler) { described_class.new(database_type_version) }

  describe '#supports_logical_replication?' do
    context 'with PostgreSQL 10+' do
      it 'returns true for version 10' do
        database_type_version.version = '10.0'
        expect(postgresql_handler.supports_logical_replication?).to be true
      end

      it 'returns true for version 15' do
        database_type_version.version = '15.0'
        expect(postgresql_handler.supports_logical_replication?).to be true
      end

      it 'returns true for version 16' do
        database_type_version.version = '16.1'
        expect(postgresql_handler.supports_logical_replication?).to be true
      end
    end

    context 'with PostgreSQL 9.x' do
      it 'returns false for version 9.6' do
        database_type_version.version = '9.6'
        expect(postgresql_handler.supports_logical_replication?).to be false
      end

      it 'returns false for version 9.5' do
        database_type_version.version = '9.5'
        expect(postgresql_handler.supports_logical_replication?).to be false
      end
    end
  end

  describe '#supports_streaming_replication?' do
    context 'with PostgreSQL 9+' do
      it 'returns true for version 9.0' do
        database_type_version.version = '9.0'
        expect(postgresql_handler.supports_streaming_replication?).to be true
      end

      it 'returns true for version 15' do
        database_type_version.version = '15.0'
        expect(postgresql_handler.supports_streaming_replication?).to be true
      end
    end

    context 'with PostgreSQL 8.x' do
      it 'returns false for version 8.4' do
        database_type_version.version = '8.4'
        expect(postgresql_handler.supports_streaming_replication?).to be false
      end
    end
  end

  describe '#generate_cloud_init_script' do
    let(:cluster) { create(:cluster, database_type: database_type) }
    let(:provider) { create(:provider) }
    let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
    let(:mock_generator) { double('cloud_init_generator') }

    before do
      allow(CloudInitGenerators::PostgresqlCloudInitGenerator).to receive(:new).and_return(mock_generator)
    end

    it 'delegates to PostgresqlCloudInitGenerator for primary node' do
      expect(CloudInitGenerators::PostgresqlCloudInitGenerator).to receive(:new).with(postgresql_handler, node)
      expect(mock_generator).to receive(:generate).with(is_replica: false).and_return('#!/bin/bash\necho "primary"')

      result = postgresql_handler.generate_cloud_init_script(node, is_replica: false)
      expect(result).to eq('#!/bin/bash\necho "primary"')
    end

    it 'delegates to PostgresqlCloudInitGenerator for replica node' do
      expect(CloudInitGenerators::PostgresqlCloudInitGenerator).to receive(:new).with(postgresql_handler, node)
      expect(mock_generator).to receive(:generate).with(is_replica: true).and_return('#!/bin/bash\necho "replica"')

      result = postgresql_handler.generate_cloud_init_script(node, is_replica: true)
      expect(result).to eq('#!/bin/bash\necho "replica"')
    end
  end

  describe '#primary_configuration_commands' do
    it 'returns array of configuration commands' do
      commands = postgresql_handler.primary_configuration_commands
      expect(commands).to be_an(Array)
      expect(commands).not_to be_empty
    end

    it 'includes wal_level configuration' do
      commands = postgresql_handler.primary_configuration_commands
      expect(commands.any? { |cmd| cmd.include?('wal_level = replica') }).to be true
    end

    it 'includes max_wal_senders configuration' do
      commands = postgresql_handler.primary_configuration_commands
      expect(commands.any? { |cmd| cmd.include?('max_wal_senders = 10') }).to be true
    end

    it 'includes archive configuration' do
      commands = postgresql_handler.primary_configuration_commands
      expect(commands.any? { |cmd| cmd.include?('archive_mode = on') }).to be true
    end

    it 'includes listen_addresses configuration' do
      commands = postgresql_handler.primary_configuration_commands
      expect(commands.any? { |cmd| cmd.include?("listen_addresses = '*'") }).to be true
    end
  end

  describe '#replica_configuration_commands' do
    it 'returns array of configuration commands' do
      commands = postgresql_handler.replica_configuration_commands
      expect(commands).to be_an(Array)
      expect(commands).not_to be_empty
    end

    it 'includes hot_standby configuration' do
      commands = postgresql_handler.replica_configuration_commands
      expect(commands.any? { |cmd| cmd.include?('hot_standby = on') }).to be true
    end

    it 'includes standby streaming delay configuration' do
      commands = postgresql_handler.replica_configuration_commands
      expect(commands.any? { |cmd| cmd.include?('max_standby_streaming_delay = 30s') }).to be true
    end
  end

  describe '#readiness_check_command' do
    it 'returns pg_isready command' do
      expect(postgresql_handler.readiness_check_command).to eq('sudo -u postgres pg_isready -q')
    end
  end

  describe '#create_sample_data_commands' do
    it 'returns array of sample data creation commands' do
      commands = postgresql_handler.create_sample_data_commands
      expect(commands).to be_an(Array)
      expect(commands).not_to be_empty
    end

    it 'includes database creation command' do
      commands = postgresql_handler.create_sample_data_commands
      expect(commands.any? { |cmd| cmd.include?('CREATE DATABASE dbchest_sample') }).to be true
    end

    it 'includes table creation commands' do
      commands = postgresql_handler.create_sample_data_commands
      expect(commands.any? { |cmd| cmd.include?('CREATE TABLE IF NOT EXISTS sample_data') }).to be true
    end
  end

  describe '#config_file_path' do
    it 'returns the PostgreSQL configuration file path' do
      expect(postgresql_handler.send(:config_file_path)).to include('postgresql.conf')
    end
  end

  describe '#major_version' do
    it 'returns the major version number' do
      database_type_version.version = '15.2'
      expect(postgresql_handler.send(:major_version)).to eq(15)
    end

    it 'handles single digit versions' do
      database_type_version.version = '9'
      expect(postgresql_handler.send(:major_version)).to eq(9)
    end
  end
end
