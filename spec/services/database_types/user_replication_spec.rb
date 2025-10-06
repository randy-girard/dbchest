require 'rails_helper'

RSpec.describe 'Database Type User Replication', type: :service do
  let(:database_type) { create(:database_type) }

  describe 'PostgreSQL' do
    let(:version) { create(:database_type_version, database_type: database_type, version: '15') }
    let(:handler) { DatabaseTypes::PostgresqlDatabaseType.new(version) }

    it 'indicates users replicate automatically' do
      expect(handler.users_replicate_automatically?).to be true
    end
  end

  describe 'MySQL' do
    let(:version) { create(:database_type_version, database_type: database_type, version: '8.0') }
    let(:handler) { DatabaseTypes::MysqlDatabaseType.new(version) }

    it 'indicates users replicate automatically' do
      expect(handler.users_replicate_automatically?).to be true
    end
  end

  describe 'MongoDB' do
    let(:version) { create(:database_type_version, database_type: database_type, version: '6.0') }
    let(:handler) { DatabaseTypes::MongodbDatabaseType.new(version) }

    it 'indicates users replicate automatically' do
      expect(handler.users_replicate_automatically?).to be true
    end
  end

  describe 'Cassandra' do
    let(:version) { create(:database_type_version, database_type: database_type, version: '4.0') }
    let(:handler) { DatabaseTypes::CassandraDatabaseType.new(version) }

    it 'indicates users replicate automatically' do
      expect(handler.users_replicate_automatically?).to be true
    end
  end

  describe 'BaseDatabaseType default behavior' do
    let(:version) { create(:database_type_version, database_type: database_type, version: '1.0') }
    
    # Create a test handler that doesn't override users_replicate_automatically?
    let(:test_handler_class) do
      Class.new(DatabaseTypes::BaseDatabaseType) do
        def supports_logical_replication?
          false
        end

        def supports_streaming_replication?
          true
        end

        def generate_cloud_init_script(node, is_replica: false)
          ""
        end
      end
    end

    let(:handler) { test_handler_class.new(version) }

    it 'defaults to true when streaming replication is supported' do
      expect(handler.users_replicate_automatically?).to be true
    end

    context 'when streaming replication is not supported' do
      let(:test_handler_no_streaming) do
        Class.new(DatabaseTypes::BaseDatabaseType) do
          def supports_logical_replication?
            false
          end

          def supports_streaming_replication?
            false
          end

          def generate_cloud_init_script(node, is_replica: false)
            ""
          end
        end
      end

      let(:handler_no_streaming) { test_handler_no_streaming.new(version) }

      it 'defaults to false' do
        expect(handler_no_streaming.users_replicate_automatically?).to be false
      end
    end
  end
end

