require 'rails_helper'

RSpec.describe ProviderType, type: :model do
  describe 'associations' do
    it { should have_many(:providers) }
    it { should have_many(:provider_type_options) }
    it { should have_many(:provider_type_node_options) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }
  end

  describe 'factory' do
    it 'creates a valid provider type' do
      provider_type = build(:provider_type)
      expect(provider_type).to be_valid
    end
  end
end
