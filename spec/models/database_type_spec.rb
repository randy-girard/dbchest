require 'rails_helper'

RSpec.describe DatabaseType, type: :model do
  let(:database_type) { build(:database_type) }

  describe 'associations' do
    it { should have_many(:database_type_versions).dependent(:destroy) }
    it { should have_many(:clusters).dependent(:restrict_with_error) }
    it { should have_many(:nodes).through(:clusters) }
  end

  describe 'validations' do
    subject { database_type }

    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name) }
    # slug presence is ensured by before_validation callback that generates slug from name
    it { should validate_uniqueness_of(:slug) }

    it 'validates slug format' do
      database_type.slug = 'invalid-slug!'
      expect(database_type).not_to be_valid
      expect(database_type.errors[:slug]).to include('only lowercase letters, numbers, and underscores allowed')
    end

    it 'allows valid slug format' do
      database_type.slug = 'valid_slug_123'
      expect(database_type).to be_valid
    end
  end

  describe 'callbacks' do
    context 'when slug is blank' do
      it 'generates slug from name' do
        database_type.name = 'PostgreSQL Database'
        database_type.slug = nil
        database_type.valid?
        expect(database_type.slug).to eq('postgresql_database')
      end

      it 'handles special characters in name' do
        database_type.name = 'MySQL 8.0 (Latest)'
        database_type.slug = nil
        database_type.valid?
        expect(database_type.slug).to eq('mysql_8_0_latest')
      end

      it 'does not generate slug when slug is present' do
        original_slug = database_type.slug
        database_type.valid?
        expect(database_type.slug).to eq(original_slug)
      end
    end
  end

  describe 'scopes' do
    describe '.active' do
      it 'returns database types with versions' do
        db_type_with_versions = create(:database_type, :with_versions)
        db_type_without_versions = create(:database_type)

        expect(DatabaseType.active).to include(db_type_with_versions)
        expect(DatabaseType.active).not_to include(db_type_without_versions)
      end
    end
  end

  describe '#default_version' do
    let(:database_type) { create(:database_type) }

    context 'when there is a default version' do
      it 'returns the default version' do
        default_version = create(:database_type_version, database_type: database_type, is_default: true)
        other_version = create(:database_type_version, database_type: database_type, is_default: false, version: '16')

        expect(database_type.default_version).to eq(default_version)
      end
    end

    context 'when there is no default version' do
      it 'returns the first version' do
        first_version = create(:database_type_version, database_type: database_type, is_default: false)
        second_version = create(:database_type_version, database_type: database_type, is_default: false, version: '16')

        expect(database_type.default_version).to eq(first_version)
      end
    end

    context 'when there are no versions' do
      it 'returns nil' do
        expect(database_type.default_version).to be_nil
      end
    end
  end

  describe '#supports_logical_replication?' do
    let(:database_type) { create(:database_type) }

    context 'for PostgreSQL' do
      before { database_type.update!(slug: 'postgresql') }

      it 'returns true when has version 10+' do
        create(:database_type_version, database_type: database_type, version: '10')
        expect(database_type.supports_logical_replication?).to be true
      end

      it 'returns false when only has versions below 10' do
        create(:database_type_version, database_type: database_type, version: '9.6')
        expect(database_type.supports_logical_replication?).to be false
      end
    end

    context 'for MySQL' do
      before { database_type.update!(slug: 'mysql') }

      it 'returns true when has version 8.0+' do
        create(:database_type_version, database_type: database_type, version: '8.0')
        expect(database_type.supports_logical_replication?).to be true
      end

      it 'returns false when only has versions below 8.0' do
        create(:database_type_version, database_type: database_type, version: '5.7')
        expect(database_type.supports_logical_replication?).to be false
      end
    end

    context 'for other database types' do
      before { database_type.update!(slug: 'mongodb') }

      it 'returns false' do
        create(:database_type_version, database_type: database_type, version: '6.0')
        expect(database_type.supports_logical_replication?).to be false
      end
    end
  end

  describe 'factory' do
    it 'creates a valid database type' do
      expect(database_type).to be_valid
    end

    it 'creates a MySQL database type with trait' do
      mysql_type = build(:database_type, :mysql)
      expect(mysql_type.name).to include('MySQL')
      expect(mysql_type.slug).to include('mysql')
    end

    it 'creates database type with versions using trait' do
      db_type = create(:database_type, :with_versions)
      expect(db_type.database_type_versions.count).to eq(2)
      expect(db_type.database_type_versions.where(is_default: true).count).to eq(1)
    end
  end
end
