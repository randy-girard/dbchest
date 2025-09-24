require 'rails_helper'

RSpec.describe Cluster, type: :model do
  let(:database_type) { create(:database_type, :with_versions) }
  let(:cluster) { build(:cluster, database_type: database_type) }

  describe 'associations' do
    it { should belong_to(:database_type) }
    it { should have_many(:nodes).dependent(:destroy) }
  end

  describe 'validations' do
    subject { cluster }

    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name) }
    # database_type presence is validated by belongs_to association
  end

  describe 'delegations' do
    it 'delegates name to database_type with prefix' do
      expect(cluster.database_type_name).to eq(database_type.name)
    end

    it 'delegates slug to database_type with prefix' do
      expect(cluster.database_type_slug).to eq(database_type.slug)
    end

    it 'delegates database_type_versions to database_type' do
      expect(cluster.database_type_versions).to eq(database_type.database_type_versions)
    end
  end

  describe 'callbacks' do
    context 'when creating a cluster without database_type' do
      it 'sets default database type to PostgreSQL' do
        postgresql_type = create(:database_type, name: 'PostgreSQL', slug: 'postgresql')
        cluster_without_type = Cluster.new(name: 'Test Cluster')
        cluster_without_type.save!
        expect(cluster_without_type.database_type).to eq(postgresql_type)
      end

      it 'sets first available database type if PostgreSQL not found' do
        other_type = create(:database_type, name: 'MySQL', slug: 'mysql')
        cluster_without_type = Cluster.new(name: 'Test Cluster')
        cluster_without_type.save!
        expect(cluster_without_type.database_type).to eq(other_type)
      end
    end
  end

  describe '#cluster_type' do
    it 'returns database type slug' do
      expect(cluster.cluster_type).to eq(database_type.slug)
    end

    it 'returns postgresql as fallback when database_type is nil' do
      cluster.database_type = nil
      expect(cluster.cluster_type).to eq('postgresql')
    end
  end

  describe '#available_versions' do
    it 'returns ordered database type versions' do
      cluster.save!
      expect(cluster.available_versions).to eq(database_type.database_type_versions.order(:version))
    end

    it 'returns empty array when database_type is nil' do
      cluster.database_type = nil
      expect(cluster.available_versions).to eq([])
    end
  end

  describe '#default_version' do
    it 'returns database type default version' do
      cluster.save!
      expect(cluster.default_version).to eq(database_type.default_version)
    end
  end

  describe '#supports_mixed_versions?' do
    it 'returns true when database type supports logical replication' do
      allow(database_type).to receive(:supports_logical_replication?).and_return(true)
      expect(cluster.supports_mixed_versions?).to be true
    end

    it 'returns false when database type does not support logical replication' do
      allow(database_type).to receive(:supports_logical_replication?).and_return(false)
      expect(cluster.supports_mixed_versions?).to be false
    end

    it 'returns false when database_type is nil' do
      cluster.database_type = nil
      expect(cluster.supports_mixed_versions?).to be false
    end
  end

  describe 'factory' do
    it 'creates a valid cluster' do
      expect(cluster).to be_valid
    end

    it 'creates a cluster with database type' do
      cluster.save!
      expect(cluster.database_type).to be_present
    end
  end
end
