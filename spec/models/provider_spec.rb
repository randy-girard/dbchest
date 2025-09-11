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

  describe 'factory' do
    it 'creates a valid provider' do
      provider = build(:provider)
      expect(provider).to be_valid
    end
  end

  describe '#build_provider_settings!' do
    let(:provider) { create(:provider) }
    
    it 'builds provider settings based on provider type options' do
      expect(provider).to respond_to(:build_provider_settings!)
    end
  end

  describe '#provider_settings_object' do
    let(:provider) { create(:provider) }
    
    it 'returns an OpenStruct with provider settings' do
      expect(provider).to respond_to(:provider_settings_object)
    end
  end

  describe '#terraform_vars' do
    let(:provider) { create(:provider) }
    
    it 'returns a hash of terraform variables' do
      expect(provider).to respond_to(:terraform_vars)
      expect(provider.terraform_vars).to be_a(Hash)
    end
  end

  describe '#api_client' do
    let(:provider) { create(:provider) }
    
    it 'returns the appropriate API client based on provider type' do
      expect(provider).to respond_to(:api_client)
    end
  end
end
