require 'rails_helper'

RSpec.describe Provider, type: :model do
  describe 'associations' do
    it { should belong_to(:provider_type) }
    it { should have_many(:nodes).dependent(:destroy) }
    it { should have_many(:provider_settings).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }
  end

  describe 'nested attributes' do
    it { should accept_nested_attributes_for(:provider_settings) }
  end
end
