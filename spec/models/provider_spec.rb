require 'rails_helper'

RSpec.describe Provider, type: :model do
  let(:provider_type) { create(:provider_type) }
  let(:provider) { build(:provider, provider_type: provider_type) }

  describe 'associations' do
    it { should belong_to(:provider_type) }
    it { should have_many(:nodes).dependent(:destroy) }
    it { should have_many(:provider_settings).dependent(:destroy) }
  end

  describe 'validations' do
    subject { provider }

    it { should validate_presence_of(:name) }

    it 'validates provider_type_id inclusion' do
      provider.provider_type_id = 999999
      expect(provider).not_to be_valid
      expect(provider.errors[:provider_type_id]).to include('is not included in the list')
    end
  end

  describe 'nested attributes' do
    it { should accept_nested_attributes_for(:provider_settings) }
  end

  describe '#build_provider_settings!' do
    let!(:option1) { create(:provider_type_option, provider_type: provider_type, key: 'api_url', label: 'API URL') }
    let!(:option2) { create(:provider_type_option, provider_type: provider_type, key: 'username', label: 'Username') }

    before { provider.save! }

    it 'builds provider settings for all provider type options' do
      provider.build_provider_settings!
      provider.save!

      expect(provider.provider_settings.count).to eq(2)
      expect(provider.provider_settings.map(&:key)).to contain_exactly('api_url', 'username')
    end

    it 'does not duplicate existing provider settings' do
      create(:provider_setting, provider: provider, provider_type_option: option1, key: 'api_url', value: 'existing_value')
      provider.build_provider_settings!
      provider.save!

      provider.reload
      expect(provider.provider_settings.count).to eq(2)
      expect(provider.provider_settings.select { |ps| ps.key == 'api_url' }.count).to eq(1)
    end
  end

  describe '#provider_settings_object' do
    let!(:option1) { create(:provider_type_option, provider_type: provider_type, key: 'api_url', label: 'API URL') }
    let!(:option2) { create(:provider_type_option, provider_type: provider_type, key: 'username', label: 'Username') }

    before do
      provider.save!
      create(:provider_setting, provider: provider, provider_type_option: option1, key: 'api_url', value: 'https://example.com')
      create(:provider_setting, provider: provider, provider_type_option: option2, key: 'username', value: 'admin')
    end

    it 'returns OpenStruct with provider settings' do
      settings_object = provider.provider_settings_object

      expect(settings_object).to be_a(OpenStruct)
      expect(settings_object.api_url).to eq('https://example.com')
      expect(settings_object.username).to eq('admin')
    end
  end

  describe '#terraform_vars' do
    before do
      provider.save!
      create(:provider_setting, provider: provider, key: 'api_url', value: 'https://example.com')
      create(:provider_setting, provider: provider, key: 'username', value: 'admin')
    end

    it 'returns hash of provider settings' do
      vars = provider.terraform_vars

      expect(vars).to be_a(Hash)
      expect(vars['api_url']).to eq('https://example.com')
      expect(vars['username']).to eq('admin')
    end
  end

  describe '#api_client' do
    context 'for Proxmox provider' do
      before { provider_type.update!(key: 'proxmox') }

      it 'returns Proxmox API client' do
        expect(ProviderClient::Base).to receive(:for_provider).with(provider).and_return(double('client'))

        client = provider.api_client
        expect(client).not_to be_nil
      end
    end

    context 'for unknown provider type' do
      before { provider_type.update!(key: 'unknown') }

      it 'returns nil and logs warning' do
        expect(Rails.logger).to receive(:warn).with(/Provider client not found/)
        expect(provider.api_client).to be_nil
      end
    end
  end

  describe 'factory' do
    it 'creates a valid provider' do
      expect(provider).to be_valid
    end

    it 'creates provider with provider_type association' do
      provider.save!
      expect(provider.provider_type).to eq(provider_type)
    end
  end
end
