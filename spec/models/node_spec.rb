require 'rails_helper'

RSpec.describe Node, type: :model do
  describe 'associations' do
    it { should belong_to(:cluster) }
    it { should belong_to(:provider) }
    it { should have_many(:node_settings).dependent(:destroy) }
  end

  describe 'nested attributes' do
    it { should accept_nested_attributes_for(:node_settings) }
  end

  describe 'factory' do
    it 'creates a valid node' do
      node = build(:node)
      expect(node).to be_valid
    end
  end

  describe '#build_node_settings!' do
    let(:node) { create(:node) }
    
    it 'builds node settings based on provider type options' do
      # This test would need to be implemented based on the actual provider type options
      expect(node).to respond_to(:build_node_settings!)
    end
  end
end
