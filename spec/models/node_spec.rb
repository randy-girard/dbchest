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


end
