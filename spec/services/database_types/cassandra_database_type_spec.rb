require 'rails_helper'

RSpec.describe DatabaseTypes::CassandraDatabaseType, type: :service do
  let(:database_type) { create(:database_type, slug: 'cassandra') }
  let(:database_type_version) { create(:database_type_version, database_type: database_type, version: '4.0', default_port: 9042) }
  let(:cluster) { create(:cluster, name: 'Test Cluster', database_type: database_type) }
  let(:node) { create(:node, database_type_version: database_type_version, cluster: cluster) }

  let(:handler) { described_class.new(database_type_version) }

  describe 'class registration' do
    it 'registers itself with the base class' do
      expect(DatabaseTypes::BaseDatabaseType.registry['cassandra']).to eq(described_class)
    end
  end

  describe '#supports_logical_replication?' do
    it 'returns false for Cassandra' do
      expect(handler.supports_logical_replication?).to be false
    end
  end

  describe '#supports_streaming_replication?' do
    it 'returns true for Cassandra' do
      expect(handler.supports_streaming_replication?).to be true
    end
  end

  describe '#generate_cloud_init_script' do
    it 'generates cloud init script for primary node' do
      expect(CloudInitGenerators::CassandraCloudInitGenerator).to receive(:new)
        .with(handler, node)
        .and_return(double(generate: 'cloud_init_script'))

      result = handler.generate_cloud_init_script(node, is_replica: false)
      expect(result).to eq('cloud_init_script')
    end

    it 'generates cloud init script for replica node' do
      expect(CloudInitGenerators::CassandraCloudInitGenerator).to receive(:new)
        .with(handler, node)
        .and_return(double(generate: 'replica_cloud_init_script'))

      result = handler.generate_cloud_init_script(node, is_replica: true)
      expect(result).to eq('replica_cloud_init_script')
    end
  end

  describe '#primary_configuration_commands' do
    before do
      allow(handler).to receive(:cluster_name).and_return('test_cluster')
      allow(handler).to receive(:seeds_list).and_return('127.0.0.1')
      allow(handler).to receive(:listen_address).and_return('192.168.1.10')
    end

    it 'returns configuration commands for primary node' do
      commands = handler.primary_configuration_commands

      expect(commands).to be_an(Array)
      expect(commands).to include(match(/cluster_name: "test_cluster"/))
      expect(commands).to include(match(/seeds: "127.0.0.1"/))
      expect(commands).to include(match(/listen_address: 192.168.1.10/))
      expect(commands).to include(match(/auto_bootstrap: false/))
    end
  end

  describe '#replica_configuration_commands' do
    before do
      allow(handler).to receive(:cluster_name).and_return('test_cluster')
      allow(handler).to receive(:seeds_list).and_return('127.0.0.1')
      allow(handler).to receive(:listen_address).and_return('192.168.1.11')
    end

    it 'returns configuration commands for replica node' do
      commands = handler.replica_configuration_commands

      expect(commands).to be_an(Array)
      expect(commands).to include(match(/cluster_name: "test_cluster"/))
      expect(commands).to include(match(/seeds: "127.0.0.1"/))
      expect(commands).to include(match(/listen_address: 192.168.1.11/))
      expect(commands).to include(match(/auto_bootstrap: true/))
    end
  end

  describe '#readiness_check_command' do
    before do
      allow(handler).to receive(:listen_address).and_return('192.168.1.10')
    end

    it 'returns cqlsh command to check cluster status' do
      command = handler.readiness_check_command
      expect(command).to eq("cqlsh -e 'DESCRIBE CLUSTER' 192.168.1.10 9042")
    end
  end

  describe '#create_sample_data_commands' do
    before do
      allow(handler).to receive(:listen_address).and_return('192.168.1.10')
      allow(handler).to receive(:replication_factor).and_return(1)
    end

    it 'returns commands to create sample keyspace and data' do
      commands = handler.create_sample_data_commands

      expect(commands).to be_an(Array)
      expect(commands.join(' ')).to include('CREATE KEYSPACE IF NOT EXISTS dbchest_sample')
      expect(commands.join(' ')).to include("'replication_factor': 1")
      expect(commands.join(' ')).to include('CREATE TABLE IF NOT EXISTS sample_data')
      expect(commands.join(' ')).to include('INSERT INTO sample_data')
    end
  end

  describe '#recovery_check_command' do
    it 'returns nodetool status command' do
      command = handler.recovery_check_command
      expect(command).to eq("nodetool status | grep -q 'UN'")
    end
  end

  describe '#replication_lag_check_commands' do
    it 'returns commands to check replication lag' do
      commands = handler.replication_lag_check_commands

      expect(commands).to be_an(Array)
      expect(commands).to include(match(/nodetool netstats/))
      expect(commands).to include(match(/nodetool compactionstats/))
    end
  end

  describe 'Cassandra-specific methods' do
    describe '#cluster_name' do
      it 'generates cluster name from database type slug' do
        expect(handler.cluster_name).to eq('dbchest_cluster')
      end

      it 'uses database type slug when available' do
        database_type.update(slug: 'custom_cassandra')
        expect(handler.cluster_name).to eq('custom_cassandra_cluster')
      end
    end

    describe '#create_keyspace_command' do
      before do
        allow(handler).to receive(:listen_address).and_return('192.168.1.10')
      end

      it 'returns command to create keyspace with default replication factor' do
        command = handler.create_keyspace_command('test_keyspace')
        expect(command).to include('CREATE KEYSPACE IF NOT EXISTS test_keyspace')
        expect(command).to include("'replication_factor': 1")
      end

      it 'returns command to create keyspace with custom replication factor' do
        command = handler.create_keyspace_command('test_keyspace', 3)
        expect(command).to include("'replication_factor': 3")
      end
    end

    describe '#drop_keyspace_command' do
      before do
        allow(handler).to receive(:listen_address).and_return('192.168.1.10')
      end

      it 'returns command to drop keyspace' do
        command = handler.drop_keyspace_command('test_keyspace')
        expect(command).to include('DROP KEYSPACE IF EXISTS test_keyspace')
      end
    end

    describe '#backup_keyspace_command' do
      it 'returns nodetool snapshot command' do
        allow(Time).to receive(:current).and_return(Time.parse("2023-01-01 12:00:00"))

        command = handler.backup_keyspace_command('test_keyspace', '/backup/path')
        expect(command).to include('nodetool snapshot test_keyspace')
        expect(command).to include('-t 20230101_120000')
      end
    end

    describe '#restore_keyspace_command' do
      it 'returns nodetool refresh command' do
        command = handler.restore_keyspace_command('test_keyspace', '/backup/path')
        expect(command).to eq('nodetool refresh test_keyspace')
      end
    end

    describe '#node_status_command' do
      it 'returns nodetool status command' do
        expect(handler.node_status_command).to eq('nodetool status')
      end
    end

    describe '#node_info_command' do
      it 'returns nodetool info command' do
        expect(handler.node_info_command).to eq('nodetool info')
      end
    end

    describe '#repair_command' do
      it 'returns repair command for specific keyspace' do
        command = handler.repair_command('test_keyspace')
        expect(command).to eq('nodetool repair test_keyspace')
      end

      it 'returns repair command for all keyspaces when none specified' do
        command = handler.repair_command
        expect(command).to eq('nodetool repair')
      end
    end

    describe '#cleanup_command' do
      it 'returns nodetool cleanup command' do
        expect(handler.cleanup_command).to eq('nodetool cleanup')
      end
    end

    describe '#flush_command' do
      it 'returns nodetool flush command' do
        expect(handler.flush_command).to eq('nodetool flush')
      end
    end
  end

  describe 'playbook names' do
    describe '#primary_playbook' do
      it 'returns create_node.yml' do
        expect(handler.primary_playbook).to eq('create_node.yml')
      end
    end

    describe '#replica_playbook' do
      it 'returns add_node.yml' do
        expect(handler.replica_playbook).to eq('add_node.yml')
      end
    end

    describe '#cleanup_playbook' do
      it 'returns remove_node.yml' do
        expect(handler.cleanup_playbook).to eq('remove_node.yml')
      end
    end

    describe '#primary_replication_playbook' do
      it 'returns expand_cluster.yml' do
        expect(handler.primary_replication_playbook).to eq('expand_cluster.yml')
      end
    end
  end

  describe 'private methods' do
    describe '#config_file_path' do
      it 'returns Cassandra config file path' do
        expect(handler.send(:config_file_path)).to eq('/etc/cassandra/cassandra.yaml')
      end
    end

    describe '#data_directory_path' do
      it 'returns Cassandra data directory path' do
        expect(handler.send(:data_directory_path)).to eq('/var/lib/cassandra')
      end
    end

    describe '#log_directory_path' do
      it 'returns Cassandra log directory path' do
        expect(handler.send(:log_directory_path)).to eq('/var/log/cassandra')
      end
    end
  end
end
