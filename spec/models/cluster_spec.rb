require 'rails_helper'

RSpec.describe Cluster, type: :model do
  describe 'associations' do
    it { should have_many(:nodes).dependent(:destroy) }
  end

  describe 'validations' do
    # Add validations as they exist in the model
  end

  describe 'factory' do
    it 'creates a valid cluster' do
      cluster = build(:cluster)
      expect(cluster).to be_valid
    end
  end
end
