require 'rails_helper'

RSpec.describe DatabaseTypeVersion, type: :model do
  let(:database_type) { create(:database_type) }
  let(:database_type_version) { build(:database_type_version, database_type: database_type) }

  describe 'associations' do
    it { should belong_to(:database_type) }
    it { should have_many(:nodes).dependent(:restrict_with_error) }
  end

  describe 'validations' do
    it { should validate_presence_of(:version) }
    it { should validate_presence_of(:install_command) }
    it { should validate_presence_of(:default_port) }
    it { should validate_presence_of(:service_name) }

    it 'validates version uniqueness within database type' do
      create(:database_type_version, database_type: database_type, version: '15')
      duplicate_version = build(:database_type_version, database_type: database_type, version: '15')
      
      expect(duplicate_version).not_to be_valid
      expect(duplicate_version.errors[:version]).to include('has already been taken')
    end

    it 'allows same version for different database types' do
      other_database_type = create(:database_type, name: 'MySQL', slug: 'mysql')
      create(:database_type_version, database_type: database_type, version: '15')
      other_version = build(:database_type_version, database_type: other_database_type, version: '15')
      
      expect(other_version).to be_valid
    end

    it 'validates default_port is greater than 0' do
      database_type_version.default_port = 0
      expect(database_type_version).not_to be_valid
      expect(database_type_version.errors[:default_port]).to include('must be greater than 0')
    end
  end

  describe 'callbacks' do
    describe 'ensure_single_default' do
      it 'sets other versions to non-default when setting a version as default' do
        existing_default = create(:database_type_version, database_type: database_type, is_default: true)
        new_default = create(:database_type_version, database_type: database_type, version: '16', is_default: true)
        
        existing_default.reload
        expect(existing_default.is_default).to be false
        expect(new_default.is_default).to be true
      end

      it 'does not affect other database types' do
        other_database_type = create(:database_type, name: 'MySQL', slug: 'mysql')
        other_default = create(:database_type_version, database_type: other_database_type, is_default: true)
        new_default = create(:database_type_version, database_type: database_type, is_default: true)
        
        other_default.reload
        expect(other_default.is_default).to be true
        expect(new_default.is_default).to be true
      end
    end
  end

  describe 'scopes' do
    describe '.defaults' do
      it 'returns only default versions' do
        default_version = create(:database_type_version, database_type: database_type, is_default: true)
        non_default_version = create(:database_type_version, database_type: database_type, version: '16', is_default: false)
        
        expect(DatabaseTypeVersion.defaults).to include(default_version)
        expect(DatabaseTypeVersion.defaults).not_to include(non_default_version)
      end
    end

    describe '.for_database_type' do
      it 'returns versions for specific database type slug' do
        pg_type = create(:database_type, name: 'PostgreSQL', slug: 'postgresql')
        mysql_type = create(:database_type, name: 'MySQL', slug: 'mysql')
        pg_version = create(:database_type_version, database_type: pg_type)
        mysql_version = create(:database_type_version, database_type: mysql_type)

        expect(DatabaseTypeVersion.for_database_type('postgresql')).to include(pg_version)
        expect(DatabaseTypeVersion.for_database_type('postgresql')).not_to include(mysql_version)
      end
    end
  end

  describe '#display_name' do
    it 'returns database type name and version' do
      database_type_version.save!
      expected_name = "#{database_type.name} #{database_type_version.version}"
      expect(database_type_version.display_name).to eq(expected_name)
    end
  end

  describe '#major_version' do
    it 'returns major version number for single digit' do
      database_type_version.version = '15'
      expect(database_type_version.major_version).to eq(15)
    end

    it 'returns major version number for semantic version' do
      database_type_version.version = '8.0.32'
      expect(database_type_version.major_version).to eq(8)
    end

    it 'returns major version number for decimal version' do
      database_type_version.version = '13.2'
      expect(database_type_version.major_version).to eq(13)
    end
  end

  describe '#supports_logical_replication?' do
    it 'delegates to database_type_handler' do
      handler = double('handler')
      allow(database_type_version).to receive(:database_type_handler).and_return(handler)
      allow(handler).to receive(:supports_logical_replication?).and_return(true)
      
      expect(database_type_version.supports_logical_replication?).to be true
    end
  end

  describe '#supports_streaming_replication?' do
    it 'delegates to database_type_handler' do
      handler = double('handler')
      allow(database_type_version).to receive(:database_type_handler).and_return(handler)
      allow(handler).to receive(:supports_streaming_replication?).and_return(true)
      
      expect(database_type_version.supports_streaming_replication?).to be true
    end
  end

  describe '#replication_method_for_cross_version' do
    let(:target_version) { create(:database_type_version, database_type: database_type, version: '16') }

    it 'delegates to database_type_handler for same database type' do
      handler = double('handler')
      allow(database_type_version).to receive(:database_type_handler).and_return(handler)
      allow(handler).to receive(:replication_method_for_cross_version).with(target_version).and_return('logical')
      
      expect(database_type_version.replication_method_for_cross_version(target_version)).to eq('logical')
    end

    it 'returns nil for different database types' do
      other_database_type = create(:database_type, name: 'MySQL', slug: 'mysql')
      other_version = create(:database_type_version, database_type: other_database_type)
      
      expect(database_type_version.replication_method_for_cross_version(other_version)).to be_nil
    end

    it 'returns nil for non-DatabaseTypeVersion objects' do
      expect(database_type_version.replication_method_for_cross_version('invalid')).to be_nil
    end
  end

  describe '#compatibility_notes' do
    context 'for PostgreSQL 16+' do
      before do
        database_type.update!(slug: 'postgresql')
        database_type_version.version = '16'
      end

      it 'includes Ubuntu compatibility warning' do
        notes = database_type_version.compatibility_notes
        expect(notes).to include('PostgreSQL 16+ requires Ubuntu 22.04 or later. Will fail on Ubuntu 20.04.')
      end
    end

    context 'for PostgreSQL 15' do
      before do
        database_type.update!(slug: 'postgresql')
        database_type_version.version = '15'
      end

      it 'returns empty array' do
        expect(database_type_version.compatibility_notes).to be_empty
      end
    end
  end

  describe '#ubuntu_compatible?' do
    before { database_type.update!(slug: 'postgresql') }

    context 'for PostgreSQL 16+' do
      before { database_type_version.version = '16' }

      it 'returns false for Ubuntu 20.04' do
        expect(database_type_version.ubuntu_compatible?('20.04')).to be false
      end

      it 'returns true for Ubuntu 22.04' do
        expect(database_type_version.ubuntu_compatible?('22.04')).to be true
      end

      it 'returns true when ubuntu_version is nil' do
        expect(database_type_version.ubuntu_compatible?(nil)).to be true
      end
    end

    context 'for PostgreSQL 15' do
      before { database_type_version.version = '15' }

      it 'returns true for any Ubuntu version' do
        expect(database_type_version.ubuntu_compatible?('20.04')).to be true
        expect(database_type_version.ubuntu_compatible?('22.04')).to be true
      end
    end

    context 'for non-PostgreSQL' do
      before do
        database_type.update!(slug: 'mysql')
        database_type_version.version = '8.0'
      end

      it 'returns true for any Ubuntu version' do
        expect(database_type_version.ubuntu_compatible?('20.04')).to be true
      end
    end
  end

  describe 'factory' do
    it 'creates a valid database type version' do
      expect(database_type_version).to be_valid
    end

    it 'creates PostgreSQL 12 version with trait' do
      pg12_version = build(:database_type_version, :postgresql_12, database_type: database_type)
      expect(pg12_version.version).to eq('12')
      expect(pg12_version.install_command).to include('postgresql-12')
    end

    it 'creates MySQL 8.0 version with trait' do
      mysql_type = create(:database_type, :mysql)
      mysql_version = build(:database_type_version, :mysql_8, database_type: mysql_type)
      expect(mysql_version.version).to eq('8.0')
      expect(mysql_version.default_port).to eq(3306)
    end
  end
end
