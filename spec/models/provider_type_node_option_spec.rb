require 'rails_helper'

RSpec.describe ProviderTypeNodeOption, type: :model do
  let(:provider_type) { create(:provider_type) }
  let(:provider_type_node_option) { build(:provider_type_node_option, provider_type: provider_type) }

  describe 'associations' do
    it { should belong_to(:provider_type) }
  end

  describe 'factory' do
    it 'creates a valid provider type node option' do
      expect(provider_type_node_option).to be_valid
    end

    it 'creates template option with trait' do
      template_option = build(:provider_type_node_option, :template, provider_type: provider_type)
      expect(template_option.key).to eq('template_template')
      expect(template_option.label).to eq('Template')
    end

    it 'creates disk_size option with trait' do
      disk_option = build(:provider_type_node_option, :disk_size, provider_type: provider_type)
      expect(disk_option.key).to eq('disk_size')
      expect(disk_option.label).to eq('Disk Size')
    end

    it 'creates ip_address option with trait' do
      ip_option = build(:provider_type_node_option, :ip_address, provider_type: provider_type)
      expect(ip_option.key).to eq('ip_address')
      expect(ip_option.label).to eq('IP Address')
    end

    it 'creates non-required option with trait' do
      non_required_option = build(:provider_type_node_option, :not_required, provider_type: provider_type)
      expect(non_required_option.required).to be false
    end
  end
end
