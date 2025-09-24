require 'rails_helper'

RSpec.describe DatabaseTypes::MysqlDatabaseType, type: :service do
  let(:database_type) { create(:database_type, slug: 'mysql') }
  let(:database_type_version) { create(:database_type_version, database_type: database_type, version: '8.0') }
  let(:mysql_handler) { described_class.new(database_type_version) }

  describe '#supports_logical_replication?' do
    context 'with MySQL 8+' do
      it 'returns true for version 8.0' do
        database_type_version.version = '8.0'
        expect(mysql_handler.supports_logical_replication?).to be true
      end

      it 'returns true for version 8.1' do
        database_type_version.version = '8.1'
        expect(mysql_handler.supports_logical_replication?).to be true
      end
    end

    context 'with MySQL 5.x and 7.x' do
      it 'returns false for version 5.7' do
        database_type_version.version = '5.7'
        expect(mysql_handler.supports_logical_replication?).to be false
      end

      it 'returns false for version 7.0' do
        database_type_version.version = '7.0'
        expect(mysql_handler.supports_logical_replication?).to be false
      end
    end
  end

  describe '#supports_streaming_replication?' do
    context 'with MySQL 5+' do
      it 'returns true for version 5.0' do
        database_type_version.version = '5.0'
        expect(mysql_handler.supports_streaming_replication?).to be true
      end

      it 'returns true for version 5.7' do
        database_type_version.version = '5.7'
        expect(mysql_handler.supports_streaming_replication?).to be true
      end

      it 'returns true for version 8.0' do
        database_type_version.version = '8.0'
        expect(mysql_handler.supports_streaming_replication?).to be true
      end
    end

    context 'with MySQL 4.x' do
      it 'returns false for version 4.1' do
        database_type_version.version = '4.1'
        expect(mysql_handler.supports_streaming_replication?).to be false
      end
    end
  end

  describe '#generate_cloud_init_script' do
    let(:cluster) { create(:cluster, database_type: database_type) }
    let(:provider) { create(:provider) }
    let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }
    let(:mock_generator) { double('cloud_init_generator') }

    before do
      allow(CloudInitGenerators::MysqlCloudInitGenerator).to receive(:new).and_return(mock_generator)
    end

    it 'delegates to MysqlCloudInitGenerator for primary node' do
      expect(CloudInitGenerators::MysqlCloudInitGenerator).to receive(:new).with(mysql_handler, node)
      expect(mock_generator).to receive(:generate).with(is_replica: false).and_return('#!/bin/bash\necho "primary"')

      result = mysql_handler.generate_cloud_init_script(node, is_replica: false)
      expect(result).to eq('#!/bin/bash\necho "primary"')
    end

    it 'delegates to MysqlCloudInitGenerator for replica node' do
      expect(CloudInitGenerators::MysqlCloudInitGenerator).to receive(:new).with(mysql_handler, node)
      expect(mock_generator).to receive(:generate).with(is_replica: true).and_return('#!/bin/bash\necho "replica"')

      result = mysql_handler.generate_cloud_init_script(node, is_replica: true)
      expect(result).to eq('#!/bin/bash\necho "replica"')
    end
  end

  describe '#primary_configuration_commands' do
    it 'returns array of configuration commands' do
      commands = mysql_handler.primary_configuration_commands
      expect(commands).to be_an(Array)
      expect(commands).not_to be_empty
    end

    it 'includes server-id configuration' do
      commands = mysql_handler.primary_configuration_commands
      expect(commands.any? { |cmd| cmd.include?('server-id = 1') }).to be true
    end

    it 'includes log-bin configuration' do
      commands = mysql_handler.primary_configuration_commands
      expect(commands.any? { |cmd| cmd.include?('log-bin = mysql-bin') }).to be true
    end

    it 'includes binlog-format configuration' do
      commands = mysql_handler.primary_configuration_commands
      expect(commands.any? { |cmd| cmd.include?('binlog-format = ROW') }).to be true
    end

    it 'includes GTID configuration' do
      commands = mysql_handler.primary_configuration_commands
      expect(commands.any? { |cmd| cmd.include?('gtid-mode = ON') }).to be true
      expect(commands.any? { |cmd| cmd.include?('enforce-gtid-consistency = ON') }).to be true
    end

    it 'includes bind-address configuration' do
      commands = mysql_handler.primary_configuration_commands
      expect(commands.any? { |cmd| cmd.include?('bind-address = 0.0.0.0') }).to be true
    end
  end

  describe '#replica_configuration_commands' do
    it 'returns array of configuration commands' do
      commands = mysql_handler.replica_configuration_commands
      expect(commands).to be_an(Array)
      expect(commands).not_to be_empty
    end

    it 'includes server-id configuration' do
      commands = mysql_handler.replica_configuration_commands
      expect(commands.any? { |cmd| cmd.include?('server-id = 2') }).to be true
    end

    it 'includes read-only configuration' do
      commands = mysql_handler.replica_configuration_commands
      expect(commands.any? { |cmd| cmd.include?('read-only = ON') }).to be true
      expect(commands.any? { |cmd| cmd.include?('super-read-only = ON') }).to be true
    end

    it 'includes relay-log configuration' do
      commands = mysql_handler.replica_configuration_commands
      expect(commands.any? { |cmd| cmd.include?('relay-log = mysql-relay-bin') }).to be true
    end
  end

  describe '#readiness_check_command' do
    it 'returns mysqladmin ping command' do
      expect(mysql_handler.readiness_check_command).to eq('mysqladmin ping')
    end
  end

  describe '#create_sample_data_commands' do
    it 'returns array of sample data creation commands' do
      commands = mysql_handler.create_sample_data_commands
      expect(commands).to be_an(Array)
      expect(commands).not_to be_empty
    end

    it 'includes database creation command' do
      commands = mysql_handler.create_sample_data_commands
      expect(commands.any? { |cmd| cmd.include?('CREATE DATABASE IF NOT EXISTS dbchest_sample') }).to be true
    end

    it 'includes table creation commands' do
      commands = mysql_handler.create_sample_data_commands
      expect(commands.any? { |cmd| cmd.include?('CREATE TABLE IF NOT EXISTS sample_data') }).to be true
    end

    it 'includes sample data insertion' do
      commands = mysql_handler.create_sample_data_commands
      expect(commands.any? { |cmd| cmd.include?("INSERT INTO sample_data (name) VALUES ('Initial Data')") }).to be true
    end
  end

  describe '#config_file_path' do
    it 'returns the MySQL configuration file path' do
      expect(mysql_handler.send(:config_file_path)).to include('mysql')
    end
  end

  describe '#major_version' do
    it 'returns the major version number' do
      database_type_version.version = '8.0.32'
      expect(mysql_handler.send(:major_version)).to eq(8)
    end

    it 'handles single digit versions' do
      database_type_version.version = '5'
      expect(mysql_handler.send(:major_version)).to eq(5)
    end
  end
end
