require 'rails_helper'

RSpec.describe NodeSetting, type: :model do
  let(:database_type) { create(:database_type, :with_versions) }
  let(:cluster) { create(:cluster, database_type: database_type) }
  let(:provider) { create(:provider) }
  let(:node) { create(:node, cluster: cluster, provider: provider, database_type_version: database_type.database_type_versions.first) }
  let(:provider_type_node_option) { create(:provider_type_node_option, provider_type: provider.provider_type) }
  let(:node_setting) { build(:node_setting, node: node, provider_type_node_option: provider_type_node_option) }

  describe 'associations' do
    it { should belong_to(:node) }
    it { should belong_to(:provider_type_node_option) }
  end

  describe 'validations' do
    it 'validates key uniqueness within node and provider_type_node_option scope' do
      create(:node_setting, node: node, provider_type_node_option: provider_type_node_option, key: 'test_key')
      duplicate_setting = build(:node_setting, node: node, provider_type_node_option: provider_type_node_option, key: 'test_key')

      expect(duplicate_setting).not_to be_valid
      expect(duplicate_setting.errors[:key]).to include('has already been taken')
    end

    it 'allows same key for different nodes' do
      other_node = create(:node, cluster: cluster, provider: provider, database_type_version: database_type.database_type_versions.first)
      create(:node_setting, node: node, provider_type_node_option: provider_type_node_option, key: 'test_key')
      other_setting = build(:node_setting, node: other_node, provider_type_node_option: provider_type_node_option, key: 'test_key')

      expect(other_setting).to be_valid
    end

    context 'when provider_type_node_option is required' do
      before { provider_type_node_option.update!(required: true) }

      it 'validates presence of value' do
        node_setting.value = nil
        expect(node_setting).not_to be_valid
        expect(node_setting.errors[:value]).to include("can't be blank")
      end

      it 'allows blank value when not required' do
        provider_type_node_option.update!(required: false)
        node_setting.value = nil
        expect(node_setting).to be_valid
      end
    end
  end

  describe 'encryption' do
    it 'encrypts value' do
      node_setting.save!

      # Check that the raw database value is encrypted (not the same as the original)
      raw_record = NodeSetting.connection.select_one(
        "SELECT value FROM node_settings WHERE id = #{node_setting.id}"
      )

      expect(raw_record['value']).not_to eq(node_setting.value)
    end

    it 'decrypts value when accessed' do
      original_value = node_setting.value

      node_setting.save!
      node_setting.reload

      expect(node_setting.value).to eq(original_value)
    end
  end

  describe 'factory' do
    it 'creates a valid node setting' do
      expect(node_setting).to be_valid
    end

    it 'creates template setting with trait' do
      template_setting = build(:node_setting, :template, node: node)
      expect(template_setting.key).to eq('template_template')
      expect(template_setting.value).to eq('ubuntu-22.04-template')
    end

    it 'creates disk_size setting with trait' do
      disk_setting = build(:node_setting, :disk_size, node: node)
      expect(disk_setting.key).to eq('disk_size')
      expect(disk_setting.value).to eq('20G')
    end

    it 'creates ip_address setting with trait' do
      ip_setting = build(:node_setting, :ip_address, node: node)
      expect(ip_setting.key).to eq('ip_address')
      expect(ip_setting.value).to eq('192.168.1.100')
    end
  end
end
