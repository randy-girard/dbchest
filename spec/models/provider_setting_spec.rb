require 'rails_helper'

RSpec.describe ProviderSetting, type: :model do
  let(:provider) { create(:provider) }
  let(:provider_type_option) { create(:provider_type_option, provider_type: provider.provider_type) }
  let(:provider_setting) { build(:provider_setting, provider: provider, provider_type_option: provider_type_option) }

  describe 'associations' do
    it { should belong_to(:provider) }
    it { should belong_to(:provider_type_option) }
  end

  describe 'validations' do
    it { should validate_presence_of(:key) }
    it { should validate_presence_of(:value) }
  end

  describe 'encryption' do
    it 'encrypts key and value' do
      provider_setting.save!
      
      # Check that the raw database values are encrypted (not the same as the original)
      raw_record = ProviderSetting.connection.select_one(
        "SELECT key, value FROM provider_settings WHERE id = #{provider_setting.id}"
      )
      
      expect(raw_record['key']).not_to eq(provider_setting.key)
      expect(raw_record['value']).not_to eq(provider_setting.value)
    end

    it 'decrypts key and value when accessed' do
      original_key = provider_setting.key
      original_value = provider_setting.value
      
      provider_setting.save!
      provider_setting.reload
      
      expect(provider_setting.key).to eq(original_key)
      expect(provider_setting.value).to eq(original_value)
    end
  end

  describe 'factory' do
    it 'creates a valid provider setting' do
      expect(provider_setting).to be_valid
    end

    it 'creates username setting with trait' do
      username_setting = build(:provider_setting, :username, provider: provider)
      expect(username_setting.key).to eq('username')
      expect(username_setting.value).to eq('root@pam')
    end

    it 'creates password setting with trait' do
      password_setting = build(:provider_setting, :password, provider: provider)
      expect(password_setting.key).to eq('password')
      expect(password_setting.value).to eq('secret_password')
    end
  end
end
