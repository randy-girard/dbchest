require 'rails_helper'

RSpec.describe ProviderTypeOption, type: :model do
  let(:provider_type) { create(:provider_type) }
  let(:provider_type_option) { build(:provider_type_option, provider_type: provider_type) }

  describe 'associations' do
    it { should belong_to(:provider_type) }
    it { should have_many(:provider_settings) }
  end

  describe 'factory' do
    it 'creates a valid provider type option' do
      expect(provider_type_option).to be_valid
    end

    it 'creates username option with trait' do
      username_option = build(:provider_type_option, :username, provider_type: provider_type)
      expect(username_option.key).to eq('username')
      expect(username_option.label).to eq('Username')
    end

    it 'creates password option with trait' do
      password_option = build(:provider_type_option, :password, provider_type: provider_type)
      expect(password_option.key).to eq('password')
      expect(password_option.label).to eq('Password')
    end

    it 'creates non-required option with trait' do
      non_required_option = build(:provider_type_option, :not_required, provider_type: provider_type)
      expect(non_required_option.required).to be false
    end

    it 'creates non-sensitive option with trait' do
      non_sensitive_option = build(:provider_type_option, :not_sensitive, provider_type: provider_type)
      expect(non_sensitive_option.sensitive).to be false
    end
  end
end
