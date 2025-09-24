require 'rails_helper'

RSpec.describe DatabaseTypes::BaseDatabaseType, type: :service do
  let(:database_type) { create(:database_type, slug: 'postgresql') }
  let(:database_type_version) { create(:database_type_version, database_type: database_type, version: '15.0') }
  let(:base_handler) { described_class.new(database_type_version) }

  describe '#initialize' do
    it 'sets the database_type_version' do
      expect(base_handler.database_type_version).to eq(database_type_version)
    end
  end

  describe '#database_type' do
    it 'returns the database type slug' do
      expect(base_handler.database_type).to eq('postgresql')
    end
  end

  describe '#version' do
    it 'returns the version' do
      expect(base_handler.version).to eq('15.0')
    end
  end

  describe '#supports_logical_replication?' do
    it 'raises NotImplementedError' do
      expect {
        base_handler.supports_logical_replication?
      }.to raise_error(NotImplementedError, /must implement #supports_logical_replication?/)
    end
  end

  describe '#supports_streaming_replication?' do
    it 'raises NotImplementedError' do
      expect {
        base_handler.supports_streaming_replication?
      }.to raise_error(NotImplementedError, /must implement #supports_streaming_replication?/)
    end
  end

  describe '#generate_cloud_init_script' do
    let(:cluster) { create(:cluster, database_type: database_type) }
    let(:provider) { create(:provider) }
    let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type_version) }

    it 'raises NotImplementedError' do
      expect {
        base_handler.generate_cloud_init_script(node)
      }.to raise_error(NotImplementedError, /must implement #generate_cloud_init_script/)
    end
  end

  describe '#replication_method_for_cross_version' do
    let(:target_version) { create(:database_type_version, database_type: database_type, version: '16.0') }

    context 'when versions are different' do
      context 'and both support logical replication' do
        before do
          allow(base_handler).to receive(:supports_logical_replication?).and_return(true)
          allow(target_version).to receive(:supports_logical_replication?).and_return(true)
        end

        it 'returns logical replication method' do
          expect(base_handler.replication_method_for_cross_version(target_version)).to eq('logical')
        end
      end

      context 'and logical replication is not supported' do
        before do
          allow(base_handler).to receive(:supports_logical_replication?).and_return(false)
          allow(target_version).to receive(:supports_logical_replication?).and_return(false)
        end

        it 'returns nil' do
          expect(base_handler.replication_method_for_cross_version(target_version)).to be_nil
        end
      end

      context 'and only source supports logical replication' do
        before do
          allow(base_handler).to receive(:supports_logical_replication?).and_return(true)
          allow(target_version).to receive(:supports_logical_replication?).and_return(false)
        end

        it 'returns nil' do
          expect(base_handler.replication_method_for_cross_version(target_version)).to be_nil
        end
      end
    end

    context 'when versions are the same' do
      let(:same_version) { create(:database_type_version, database_type: database_type, version: '15.1') }

      context 'and streaming replication is supported' do
        before do
          allow(base_handler).to receive(:supports_streaming_replication?).and_return(true)
        end

        it 'returns streaming replication method' do
          expect(base_handler.replication_method_for_cross_version(database_type_version)).to eq('streaming')
        end
      end

      context 'and streaming replication is not supported' do
        before do
          allow(base_handler).to receive(:supports_streaming_replication?).and_return(false)
        end

        it 'returns nil' do
          expect(base_handler.replication_method_for_cross_version(database_type_version)).to be_nil
        end
      end
    end
  end

  describe '#ansible_playbook_directory' do
    it 'returns the correct path' do
      expected_path = 'lib/ansible/postgresql'
      expect(base_handler.ansible_playbook_directory).to eq(expected_path)
    end
  end

  describe '.for_database_type_version' do
    context 'with PostgreSQL database type' do
      it 'returns PostgresqlDatabaseType instance' do
        handler = described_class.for_database_type_version(database_type_version)
        expect(handler).to be_a(DatabaseTypes::PostgresqlDatabaseType)
      end
    end

    context 'with MySQL database type' do
      let(:mysql_type) { create(:database_type, slug: 'mysql') }
      let(:mysql_version) { create(:database_type_version, database_type: mysql_type) }

      it 'returns MysqlDatabaseType instance' do
        handler = described_class.for_database_type_version(mysql_version)
        expect(handler).to be_a(DatabaseTypes::MysqlDatabaseType)
      end
    end

    context 'with unknown database type' do
      let(:unknown_type) { create(:database_type, slug: 'unknown') }
      let(:unknown_version) { create(:database_type_version, database_type: unknown_type) }

      it 'raises ArgumentError' do
        expect {
          described_class.for_database_type_version(unknown_version)
        }.to raise_error(ArgumentError, /Unknown database type: unknown/)
      end
    end
  end
end
